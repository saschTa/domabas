//go:build integration

package repos

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	identitysources "github.com/domabas/domabas/backend/internal/data/identity/datasources"
	identitysecurity "github.com/domabas/domabas/backend/internal/data/identity/security"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	interfaces "github.com/domabas/domabas/backend/internal/domain/identity/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/identity/models"
	services "github.com/domabas/domabas/backend/internal/domain/identity/services"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type independentActivityPolicy struct {
	interfaces.IdentityAuthorizer
	deny            map[string]bool
	once            sync.Once
	barrier, resume chan struct{}
}

func (p *independentActivityPolicy) Allows(actor m.IdentityPrincipal, permission m.IdentityPermission) bool {
	if permission == "activity:read:own" && p.barrier != nil {
		p.once.Do(func() { close(p.barrier); <-p.resume })
	}
	return !p.deny[string(permission)] && p.IdentityAuthorizer.Allows(actor, permission)
}

func independentActivityRepository(t *testing.T, pool *pgxpool.Pool, policy interfaces.IdentityAuthorizer) *services.IdentityActivityService {
	t.Helper()
	source, err := postgres.NewPostgresDataSource(t.Context(), pool.Config().ConnString())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(source.Close)
	dataSource := identitysources.NewIdentityDataSource(source.Database())
	return services.NewIdentityActivityService(NewIdentityActivityRepository(dataSource), identityApplication(t, NewIdentityRepository(dataSource)), policy)
}

func TestIndependentActivityUsesPerKindAndTitlePolicyEvenForSystemOwner(t *testing.T) {
	pool, _, _, actor := activityFixture(t)
	stamp := time.Now().UTC().Truncate(time.Microsecond)
	documentJob, document := activityDocument(t, pool, actor.AccountID, actor.UserID, stamp, &stamp, nil)
	if _, err := pool.Exec(t.Context(), `INSERT INTO documents(id,account_id,title,description,created_at) VALUES($1,$2,'Private title','',CURRENT_TIMESTAMP)`, document, actor.AccountID); err != nil {
		t.Fatal(err)
	}
	activityEmail(t, pool, actor.AccountID, actor.UserID, uuid.NewString(), "succeeded", stamp, stamp)
	activityBatch(t, pool, actor.AccountID, actor.UserID, "manual", stamp, stamp)
	policy, err := identitysecurity.NewCasbinIdentityAuthorizer()
	if err != nil {
		t.Fatal(err)
	}
	denial := &independentActivityPolicy{IdentityAuthorizer: policy, deny: map[string]bool{
		"documents:read": true, "email:manage": true, "documents:jobs:read": true, "documents:reindex": true,
	}}
	repository := independentActivityRepository(t, pool, denial)
	feed, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || len(feed.Finished) != 1 || feed.Finished[0].ID != documentJob {
		t.Fatalf("kind-specific authority was bypassed: %+v %v", feed, err)
	}
	item := feed.Finished[0]
	if item.Title != nil || item.DocumentID != nil || item.CanOpen {
		t.Fatalf("own-job access leaked content without read authority: %+v", item)
	}
	denial.deny["activity:read:own"] = true
	feed, err = repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || len(feed.Active) != 0 || len(feed.Finished) != 0 || feed.ActiveTruncated {
		t.Fatalf("system/owner identity bypassed denied activity policy: %+v %v", feed, err)
	}
}

func TestIndependentActivityAuthorizationBoundaryPermitsFinishAndRechecksNextOperation(t *testing.T) {
	pool, identities, _, actor := activityFixture(t)
	other := registerIdentityUser(t, identities, "snapshot-other@example.test")
	if _, err := pool.Exec(t.Context(), `INSERT INTO memberships(account_id,user_id,role,enabled,is_owner,claims) VALUES($1,$2,'viewer',true,false,'{}')`, other.AccountID, actor.UserID); err != nil {
		t.Fatal(err)
	}
	stamp := time.Now().UTC().Truncate(time.Microsecond)
	_, document := activityDocument(t, pool, other.AccountID, actor.UserID, stamp, &stamp, nil)
	if _, err := pool.Exec(t.Context(), `INSERT INTO documents(id,account_id,title,description,created_at) VALUES($1,$2,'Before revocation','',CURRENT_TIMESTAMP)`, document, other.AccountID); err != nil {
		t.Fatal(err)
	}
	policy, err := identitysecurity.NewCasbinIdentityAuthorizer()
	if err != nil {
		t.Fatal(err)
	}
	barrier := &independentActivityPolicy{IdentityAuthorizer: policy, barrier: make(chan struct{}), resume: make(chan struct{})}
	repository := independentActivityRepository(t, pool, barrier)
	type outcome struct {
		feed m.PersonalActivity
		err  error
	}
	result := make(chan outcome, 1)
	go func() {
		feed, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
		result <- outcome{feed, err}
	}()
	var release sync.Once
	unblock := func() { release.Do(func() { close(barrier.resume) }) }
	defer unblock()
	select {
	case <-barrier.barrier:
	case <-time.After(2 * time.Second):
		t.Fatal("activity read never reached the membership policy barrier")
	}
	writeContext, cancel := context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	tx, err := pool.Begin(writeContext)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	if _, err = tx.Exec(writeContext, `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, other.AccountID, actor.UserID); err == nil {
		_, err = tx.Exec(writeContext, `UPDATE documents SET title='After revocation' WHERE id=$1`, document)
	}
	if err == nil {
		err = tx.Commit(writeContext)
	}
	if err != nil {
		t.Fatalf("read query held authority locks or blocked a concurrent revocation: %v", err)
	}
	unblock()
	first := <-result
	if first.err != nil || len(first.feed.Finished) != 1 || first.feed.Finished[0].Title == nil || *first.feed.Finished[0].Title != "After revocation" {
		t.Fatalf("authorized operation did not finish using its permitted scope: %+v %v", first.feed, first.err)
	}
	next, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || len(next.Finished) != 0 {
		t.Fatalf("subsequent snapshot retained revoked work: %+v %v", next, err)
	}
}

func TestIndependentActivityRejectsExcessMembershipsWithoutPartialFeed(t *testing.T) {
	pool, _, repository, actor := activityFixture(t)
	_, err := pool.Exec(t.Context(), `WITH added AS (
 INSERT INTO accounts(id,name) SELECT gen_random_uuid(),'Bounded library' FROM generate_series(1,10000) RETURNING id
) INSERT INTO memberships(account_id,user_id,role,enabled,is_owner,claims) SELECT id,$1,'viewer',true,false,'{}' FROM added`, actor.UserID)
	if err != nil {
		t.Fatal(err)
	}
	feed, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if !errors.Is(err, m.ErrActivityUnavailable) || len(feed.Active) != 0 || len(feed.Finished) != 0 {
		t.Fatalf("membership cap silently produced a partial feed: %+v %v", feed, err)
	}
}
