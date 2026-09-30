//go:build integration

package repos

import (
	"errors"
	"testing"
	"time"

	security "github.com/domabas/domabas/backend/internal/data/identity/security"
	m "github.com/domabas/domabas/backend/internal/domain/identity/models"
	services "github.com/domabas/domabas/backend/internal/domain/identity/services"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func activityFixture(t *testing.T) (*pgxpool.Pool, *IdentityRepository, *services.IdentityActivityService, m.IdentityPrincipal) {
	t.Helper()
	pool, identities := identityFixture(t)
	actor := registerIdentityUser(t, identities, "activity@example.test")
	policy, err := security.NewCasbinIdentityAuthorizer()
	if err != nil {
		t.Fatal(err)
	}
	return pool, identities, services.NewIdentityActivityService(NewIdentityActivityRepository(identities.source.(IdentityActivitySource)), identityApplication(t, identities), policy), actor
}

func activityDocument(t *testing.T, pool *pgxpool.Pool, account, initiator string, created time.Time, finished *time.Time, parent *string) (string, string) {
	t.Helper()
	id, document := uuid.NewString(), uuid.NewString()
	status := "running"
	if finished != nil {
		status = "succeeded"
	}
	_, err := pool.Exec(t.Context(), `INSERT INTO document_processing_jobs(id,account_id,document_id,generation,generation_sequence,requires_extraction,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,created_at,finished_at,updated_at,initiated_by_user_id,parent_batch_id)
 VALUES($1,$2,$3,1,1,true,'upload',1,repeat('a',64),'{}',$4,'extract','machine',$5,$6,$5,NULLIF($7,'')::uuid,$8::uuid)`, id, account, document, status, created, finished, initiator, parent)
	if err != nil {
		t.Fatal(err)
	}
	return id, document
}

func activityEmail(t *testing.T, pool *pgxpool.Pool, account, owner, provider, status string, created, finished time.Time) string {
	t.Helper()
	id := uuid.NewString()
	_, err := pool.Exec(t.Context(), `INSERT INTO email_runs(id,provider_id,account_id,owner_id,provider_revision,source_generation,trigger,status,stage,created_at,finished_at) VALUES($1,$2,$3,$4,1,1,'manual',$5,'complete',$6,$7)`, id, provider, account, owner, status, created, finished)
	if err != nil {
		t.Fatal(err)
	}
	return id
}

func activityBatch(t *testing.T, pool *pgxpool.Pool, account, requester, reason string, created, finished time.Time) string {
	t.Helper()
	id := uuid.NewString()
	_, err := pool.Exec(t.Context(), `INSERT INTO document_reindex_batches(id,account_id,requester_id,reason,configuration_revision,configuration_fingerprint,cutoff_sequence,status,created_at,finished_at) VALUES($1,NULLIF($2,'')::uuid,$3,$4,1,repeat('a',64),0,'succeeded',$5,$6)`, id, account, requester, reason, created, finished)
	if err != nil {
		t.Fatal(err)
	}
	return id
}

func TestPersonalActivityFiltersBeforeCombinedFinishedLimit(t *testing.T) {
	pool, identities, repository, actor := activityFixture(t)
	other := registerIdentityUser(t, identities, "other-activity@example.test")
	base := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	ids := []string{}
	for index := range 9 {
		created, finished := base.Add(-time.Duration(index)*time.Minute), base.Add(time.Duration(index)*time.Minute)
		switch index % 3 {
		case 0:
			id, _ := activityDocument(t, pool, actor.AccountID, actor.UserID, created, &finished, nil)
			ids = append(ids, id)
		case 1:
			ids = append(ids, activityEmail(t, pool, actor.AccountID, actor.UserID, uuid.NewString(), "succeeded", created, finished))
		case 2:
			ids = append(ids, activityBatch(t, pool, actor.AccountID, actor.UserID, "manual", created, finished))
		}
	}
	newer := base.Add(30 * time.Minute)
	for range 7 {
		activityDocument(t, pool, actor.AccountID, other.UserID, newer, &newer, nil)
		activityDocument(t, pool, other.AccountID, actor.UserID, newer, &newer, nil)
		activityDocument(t, pool, actor.AccountID, "", newer, &newer, nil)
		parent := uuid.NewString()
		activityDocument(t, pool, actor.AccountID, actor.UserID, newer, &newer, &parent)
		activityEmail(t, pool, actor.AccountID, other.UserID, uuid.NewString(), "succeeded", newer, newer)
	}
	activityBatch(t, pool, "", actor.UserID, "manual", newer, newer)
	activityBatch(t, pool, actor.AccountID, actor.UserID, "configuration_change", newer, newer)
	activityBatch(t, pool, actor.AccountID, other.UserID, "manual", newer, newer)
	feed, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || len(feed.Finished) != 5 || len(feed.Active) != 0 || feed.GeneratedAt.IsZero() {
		t.Fatalf("feed=%+v err=%v", feed, err)
	}
	for index, item := range feed.Finished {
		if item.ID != ids[8-index] {
			t.Fatalf("combined finish ordering[%d]=%s, want %s", index, item.ID, ids[8-index])
		}
	}
}

func TestPersonalActivityTruncationMembershipAndLiveTitles(t *testing.T) {
	pool, identities, repository, actor := activityFixture(t)
	other := registerIdentityUser(t, identities, "shared-activity@example.test")
	if _, err := pool.Exec(t.Context(), `INSERT INTO memberships(account_id,user_id,role,enabled,is_owner,claims) VALUES($1,$2,'viewer',true,false,'{}')`, other.AccountID, actor.UserID); err != nil {
		t.Fatal(err)
	}
	base := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	ids := []string{}
	var document string
	for index := range 22 {
		id, doc := activityDocument(t, pool, other.AccountID, actor.UserID, base.Add(time.Duration(index)*time.Second), nil, nil)
		ids, document = append(ids, id), doc
	}
	if _, err := pool.Exec(t.Context(), `INSERT INTO documents(id,account_id,title,description,created_at) VALUES($1,$2,'Current live title','',CURRENT_TIMESTAMP)`, document, other.AccountID); err != nil {
		t.Fatal(err)
	}
	feed, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || len(feed.Active) != 20 || !feed.ActiveTruncated || feed.Active[0].ID != ids[21] {
		t.Fatalf("active pagination: %+v %v", feed, err)
	}
	first := feed.Active[0]
	if first.Title == nil || *first.Title != "Current live title" || first.DocumentID == nil || *first.DocumentID != document || !first.CanOpen || feed.Active[1].Title != nil || feed.Active[1].DocumentID != nil || feed.Active[1].CanOpen {
		t.Fatalf("live/deleted title and target gate: %+v", feed.Active[:2])
	}
	if _, err := pool.Exec(t.Context(), `DELETE FROM documents WHERE id=$1`, document); err != nil {
		t.Fatal(err)
	}
	feed, err = repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || feed.Active[0].Title != nil || feed.Active[0].DocumentID != nil || feed.Active[0].CanOpen {
		t.Fatalf("deleted title survived: %+v %v", feed, err)
	}
	if _, err := pool.Exec(t.Context(), `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, other.AccountID, actor.UserID); err != nil {
		t.Fatal(err)
	}
	feed, err = repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || len(feed.Active) != 0 || feed.ActiveTruncated {
		t.Fatalf("revoked library still counted: %+v %v", feed, err)
	}
}

func TestPersonalActivityRequiresFreshSessionAndCredentialRevision(t *testing.T) {
	pool, _, repository, actor := activityFixture(t)
	if _, err := pool.Exec(t.Context(), `UPDATE users SET credential_revision=credential_revision+1 WHERE id=$1`, actor.UserID); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{}); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("stale credential revision accepted: %v", err)
	}
	if _, err := pool.Exec(t.Context(), `UPDATE users SET credential_revision=credential_revision-1 WHERE id=$1`, actor.UserID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(t.Context(), `DELETE FROM sessions WHERE digest=$1`, actor.SessionDigest); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{}); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("deleted session accepted: %v", err)
	}
}

func TestPersonalActivityProviderDeletionAndChangedRunMapping(t *testing.T) {
	pool, _, repository, actor := activityFixture(t)
	provider := uuid.NewString()
	_, err := pool.Exec(t.Context(), `INSERT INTO email_providers(id,account_id,owner_id,label,host,port,mailbox,interval_minutes,max_age_days,page_size) VALUES($1,$2,$3,'Private mailbox','example.test',993,'INBOX',15,30,50)`, provider, actor.AccountID, actor.UserID)
	if err != nil {
		t.Fatal(err)
	}
	stamp := time.Now().UTC().Truncate(time.Microsecond)
	id := activityEmail(t, pool, actor.AccountID, actor.UserID, provider, "superseded", stamp, stamp)
	feed, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || len(feed.Finished) != 1 {
		t.Fatalf("feed=%+v %v", feed, err)
	}
	item := feed.Finished[0]
	if item.ID != id || item.Status != "cancelled" || item.FailureCode == nil || *item.FailureCode != "provider_changed" || item.ProviderID == nil || *item.ProviderID != provider || item.Title == nil || !item.CanOpen {
		t.Fatalf("live provider mapping: %+v", item)
	}
	if _, err := pool.Exec(t.Context(), `UPDATE email_providers SET deleted_at=CURRENT_TIMESTAMP WHERE id=$1`, provider); err != nil {
		t.Fatal(err)
	}
	feed, err = repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || len(feed.Finished) != 1 || feed.Finished[0].ProviderID != nil || feed.Finished[0].Title != nil || feed.Finished[0].CanOpen {
		t.Fatalf("deleted provider disclosure: %+v %v", feed, err)
	}
}

func TestPersonalActivityIndependentContinuationsAndStableTies(t *testing.T) {
	pool, identities, repository, actor := activityFixture(t)
	other := registerIdentityUser(t, identities, "other-pages@example.test")
	at := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	for range 23 {
		activityDocument(t, pool, actor.AccountID, actor.UserID, at, nil, nil)
	}
	for range 12 {
		activityDocument(t, pool, actor.AccountID, actor.UserID, at, &at, nil)
	}
	first, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{})
	if err != nil || len(first.Active) != 20 || len(first.Finished) != 5 || first.ActiveNextCursor == "" || first.FinishedNextCursor == "" {
		t.Fatalf("first=%+v err=%v", first, err)
	}
	newer := at.Add(time.Minute)
	activityDocument(t, pool, actor.AccountID, actor.UserID, newer, nil, nil)
	activityDocument(t, pool, actor.AccountID, actor.UserID, newer, &newer, nil)
	second, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{ActiveCursor: first.ActiveNextCursor, FinishedCursor: first.FinishedNextCursor})
	if err != nil || len(second.Active) != 3 || len(second.Finished) != 5 || second.ActiveNextCursor != "" || second.FinishedNextCursor == "" {
		t.Fatalf("second=%+v err=%v", second, err)
	}
	last, err := repository.PersonalActivity(t.Context(), actor, m.IdentityActivityPageRequest{ActiveCursor: first.ActiveNextCursor, FinishedCursor: second.FinishedNextCursor})
	if err != nil || len(last.Finished) != 2 || last.FinishedNextCursor != "" {
		t.Fatalf("last=%+v err=%v", last, err)
	}
	seen := map[string]bool{}
	for _, items := range [][]m.PersonalActivityItem{first.Active, second.Active, first.Finished, second.Finished, last.Finished} {
		for _, item := range items {
			if seen[item.ID] {
				t.Fatal("duplicate across pages")
			}
			seen[item.ID] = true
		}
	}
	if len(seen) != 35 {
		t.Fatal("incomplete history", len(seen))
	}
	for _, page := range []m.IdentityActivityPageRequest{{ActiveCursor: "invalid"}, {ActiveCursor: first.FinishedNextCursor}, {FinishedCursor: first.ActiveNextCursor}} {
		if _, err := repository.PersonalActivity(t.Context(), actor, page); err == nil {
			t.Fatal("invalid cursor accepted")
		}
	}
	if _, err := repository.PersonalActivity(t.Context(), other, m.IdentityActivityPageRequest{ActiveCursor: first.ActiveNextCursor}); err == nil {
		t.Fatal("foreign cursor accepted")
	}
}
