//go:build integration

package repos

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"testing"
	"time"

	identitysources "github.com/domabas/domabas/backend/internal/data/identity/datasources"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
	identityservices "github.com/domabas/domabas/backend/internal/domain/identity/services"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func identityFixture(t *testing.T) (*pgxpool.Pool, *IdentityRepository) {
	t.Helper()
	databaseURL := testdb.New(t)
	source, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(source.Close)
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	fixtures, err := pgxpool.New(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(fixtures.Close)
	return fixtures, NewIdentityRepository(identitysources.NewIdentityDataSource(source.Database()))
}
func identitySession() identitymodels.IdentitySessionRecord {
	expiry := time.Now().UTC().Add(time.Hour)
	return identitymodels.IdentitySessionRecord{Digest: fmt.Sprintf("%x", sha256.Sum256([]byte(uuid.NewString()))), CreatedAt: time.Now().UTC(), ExpiresAt: &expiry}
}
func registerIdentityUser(t *testing.T, r *IdentityRepository, email string) identitymodels.IdentityPrincipal {
	t.Helper()
	record := identitySession()
	p, err := identityRegisterFixture(t.Context(), r, identitymodels.IdentityRegistration{AccountID: uuid.NewString(), UserID: uuid.NewString(), AccountName: "Test account", Email: email, PasswordHash: "old-hash", CreatedAt: time.Now(), Session: record})
	if err != nil {
		t.Fatal(err)
	}
	return p
}
func createIdentityOwner(t *testing.T, r *IdentityRepository, actor identitymodels.IdentityPrincipal) identitymodels.IdentityPrincipal {
	t.Helper()
	member, err := identityCreateMemberFixture(t, r, t.Context(), actor, identitymodels.IdentityNewMember{ID: uuid.NewString(), AccountID: uuid.NewString(), Email: uuid.NewString() + "@example.test", PasswordHash: "initial", Role: identitymodels.Admin, CreatedAt: time.Now()}, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	snapshot, err := r.CredentialsByEmail(t.Context(), member.Email)
	if err != nil {
		t.Fatal(err)
	}
	p, err := r.CreateSession(t.Context(), snapshot, identitySession())
	if err != nil {
		t.Fatal(err)
	}
	if err := r.ChangePassword(t.Context(), p, snapshot, "changed", time.Now()); err != nil {
		t.Fatal(err)
	}
	snapshot, err = r.CredentialsByEmail(t.Context(), member.Email)
	if err != nil {
		t.Fatal(err)
	}
	p, err = r.CreateSession(t.Context(), snapshot, identitySession())
	if err != nil {
		t.Fatal(err)
	}
	switched, _, err := identitySwitchFixture(t, r, t.Context(), p, actor.AccountID, identitySession())
	if err != nil {
		t.Fatal(err)
	}
	return switched
}

func TestIdentityTransactionsAndSessionRevisions(t *testing.T) {
	source, r := identityFixture(t)
	owner := registerIdentityUser(t, r, "owner@example.test")
	other := registerIdentityUser(t, r, "other@example.test")
	if _, err := identityRegisterFixture(t.Context(), r, identitymodels.IdentityRegistration{AccountID: uuid.NewString(), UserID: uuid.NewString(), AccountName: "Duplicate", Email: owner.Email, PasswordHash: "hash", CreatedAt: time.Now(), Session: identitySession()}); !errors.Is(err, identitymodels.ErrConflict) {
		t.Fatalf("duplicate: %v", err)
	}
	var accounts int
	if err := source.QueryRow(t.Context(), "SELECT count(*) FROM accounts").Scan(&accounts); err != nil || accounts != 2 {
		t.Fatalf("register rollback: %d %v", accounts, err)
	}
	if _, err := identityApplication(t, r).UpdateMember(t.Context(), owner, other.UserID, identitymodels.User, nil, true); !errors.Is(err, identitymodels.ErrNotFound) {
		t.Fatalf("foreign member: %v", err)
	}
	if _, err := identityApplication(t, r).UpdateMember(t.Context(), owner, owner.UserID, identitymodels.User, nil, true); !errors.Is(err, identitymodels.ErrConflict) {
		t.Fatalf("last owner: %v", err)
	}
	snapshot, err := r.CredentialsByEmail(t.Context(), owner.Email)
	if err != nil {
		t.Fatal(err)
	}
	if err := r.ChangePassword(t.Context(), owner, snapshot, "new-hash", time.Now()); err != nil {
		t.Fatal(err)
	}
	if _, err := r.CreateSession(t.Context(), snapshot, identitySession()); !errors.Is(err, identitymodels.ErrCredentials) {
		t.Fatalf("stale verified credentials minted session: %v", err)
	}
	if _, err := identityAuthenticateFixture(t, r, t.Context(), owner.SessionDigest, time.Now()); !errors.Is(err, identitymodels.ErrUnauthorized) {
		t.Fatalf("old password session: %v", err)
	}
	if _, err := identityCreateMemberFixture(t, r, t.Context(), owner, identitymodels.IdentityNewMember{ID: uuid.NewString(), AccountID: uuid.NewString(), Email: "revoked@example.test", PasswordHash: "hash", Role: identitymodels.Viewer, CreatedAt: time.Now()}, time.Now()); !errors.Is(err, identitymodels.ErrUnauthorized) {
		t.Fatalf("stale principal mutated members: %v", err)
	}
}

func TestIdentityConcurrentAdminChangesPreserveOwnership(t *testing.T) {
	source, r := identityFixture(t)
	first := registerIdentityUser(t, r, "first@example.test")
	second := createIdentityOwner(t, r, first)
	start := make(chan struct{})
	results := make(chan error, 2)
	for _, pair := range [][2]identitymodels.IdentityPrincipal{{first, second}, {second, first}} {
		go func(actor, target identitymodels.IdentityPrincipal) {
			<-start
			_, err := identityApplication(t, r).UpdateMember(t.Context(), actor, target.UserID, identitymodels.User, nil, true)
			results <- err
		}(pair[0], pair[1])
	}
	close(start)
	a, b := <-results, <-results
	if (a == nil) == (b == nil) {
		t.Fatalf("expected one serialized change: %v / %v", a, b)
	}
	loser := a
	if loser == nil {
		loser = b
	}
	if !errors.Is(loser, identitymodels.ErrUnauthorized) && !errors.Is(loser, identitymodels.ErrForbidden) && !errors.Is(loser, identitymodels.ErrConflict) {
		t.Fatalf("loser was not rejected after role revocation: %v", loser)
	}
	var count int
	if err := source.QueryRow(t.Context(), "SELECT count(*) FROM memberships WHERE is_owner AND enabled AND account_id=$1", first.AccountID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("enabled owners %d: %v", count, err)
	}
}

func TestIdentityLogoutOrderedBeforeBlockedMutation(t *testing.T) {
	source, r := identityFixture(t)
	actor := registerIdentityUser(t, r, "actor@example.test")
	tx, err := source.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	if _, err := tx.Exec(t.Context(), "SELECT id FROM accounts WHERE id=$1 FOR UPDATE", actor.AccountID); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(t.Context(), "DELETE FROM sessions WHERE digest=$1", actor.SessionDigest); err != nil {
		t.Fatal(err)
	}
	started := make(chan struct{})
	result := make(chan error, 1)
	go func() {
		close(started)
		_, err := identityCreateMemberFixture(t, r, t.Context(), actor, identitymodels.IdentityNewMember{ID: uuid.NewString(), AccountID: uuid.NewString(), Email: "stale@example.test", PasswordHash: "hash", Role: identitymodels.Viewer, CreatedAt: time.Now()}, time.Now())
		result <- err
	}()
	<-started
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := <-result; !errors.Is(err, identitymodels.ErrUnauthorized) {
		t.Fatalf("revoked actor after row lock: %v", err)
	}
}

func TestIdentitySessionConditionsAndAccountMemberCounts(t *testing.T) {
	source, r := identityFixture(t)
	owner := registerIdentityUser(t, r, "owner@example.test")
	_ = registerIdentityUser(t, r, "elsewhere@example.test")
	member, err := identityCreateMemberFixture(t, r, t.Context(), owner, identitymodels.IdentityNewMember{ID: uuid.NewString(), AccountID: uuid.NewString(), Email: "viewer@example.test", PasswordHash: "initial", Role: identitymodels.Viewer, CreatedAt: time.Now()}, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if !member.MustChangePassword {
		t.Fatal("new member must change password")
	}
	page, err := identityApplication(t, r).ListMembers(t.Context(), owner, 1, 0)
	if err != nil || page.Total != 2 || len(page.Items) != 1 {
		t.Fatalf("account page: %+v %v", page, err)
	}
	snapshot, err := r.CredentialsByEmail(t.Context(), member.Email)
	if err != nil {
		t.Fatal(err)
	}
	session := identitySession()
	principal, err := r.CreateSession(t.Context(), snapshot, session)
	if err != nil || !principal.MustChangePassword {
		t.Fatalf("initial principal: %+v %v", principal, err)
	}
	if _, err := source.Exec(t.Context(), "UPDATE sessions SET expires_at=clock_timestamp() WHERE digest=$1", session.Digest); err != nil {
		t.Fatal(err)
	}
	if _, err := identityAuthenticateFixture(t, r, t.Context(), session.Digest, *session.ExpiresAt); !errors.Is(err, identitymodels.ErrUnauthorized) {
		t.Fatalf("expired boundary: %v", err)
	}
	if _, err := source.Exec(t.Context(), "UPDATE users SET credential_revision=credential_revision+1 WHERE id=$1", member.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := identityAuthenticateFixture(t, r, t.Context(), session.Digest, time.Now()); !errors.Is(err, identitymodels.ErrUnauthorized) {
		t.Fatalf("stale revision accepted: %v", err)
	}
	if _, err := identityAuthenticateFixture(t, r, t.Context(), fmt.Sprintf("%064d", 1), time.Now()); !errors.Is(err, identitymodels.ErrUnauthorized) {
		t.Fatalf("unknown digest accepted: %v", err)
	}
}

func TestExpiredSessionCleanupIsBounded(t *testing.T) {
	source, r := identityFixture(t)
	owner := registerIdentityUser(t, r, "cleanup@example.test")
	if _, err := source.Exec(t.Context(), "INSERT INTO sessions(digest,account_id,user_id,credential_revision,expires_at) SELECT lpad(to_hex(n),64,'0'),$1,$2,1,now()-interval '1 minute' FROM generate_series(1,250) n", owner.AccountID, owner.UserID); err != nil {
		t.Fatal(err)
	}
	if err := r.CleanupSessions(t.Context(), time.Now()); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := source.QueryRow(t.Context(), "SELECT count(*) FROM sessions WHERE expires_at<=now()").Scan(&count); err != nil || count != 50 {
		t.Fatalf("expired remainder %d %v", count, err)
	}
}

func TestIdentityConcurrentSelfDemotionsPreserveImmutableOwner(t *testing.T) {
	source, r := identityFixture(t)
	first := registerIdentityUser(t, r, "first-self@example.test")
	second := createIdentityOwner(t, r, first)
	start := make(chan struct{})
	results := make(chan error, 2)
	for _, actor := range []identitymodels.IdentityPrincipal{first, second} {
		go func() {
			<-start
			_, err := identityApplication(t, r).UpdateMember(t.Context(), actor, actor.UserID, identitymodels.User, nil, true)
			results <- err
		}()
	}
	close(start)
	a, b := <-results, <-results
	if (a == nil) == (b == nil) {
		t.Fatalf("expected exactly one self-demotion: %v / %v", a, b)
	}
	rejected := a
	if rejected == nil {
		rejected = b
	}
	if !errors.Is(rejected, identitymodels.ErrConflict) {
		t.Fatalf("last owner must receive conflict: %v", rejected)
	}
	var owners int
	if err := source.QueryRow(t.Context(), "SELECT count(*) FROM memberships WHERE account_id=$1 AND enabled AND is_owner", first.AccountID).Scan(&owners); err != nil || owners != 1 {
		t.Fatalf("enabled owners=%d %v", owners, err)
	}
}

type pausedPasswordVerifier struct{ verified, release chan struct{} }

func (p *pausedPasswordVerifier) Hash(context.Context, string) (string, error) {
	return "new-hash", nil
}
func (p *pausedPasswordVerifier) Verify(context.Context, string, string) (bool, error) {
	close(p.verified)
	<-p.release
	return true, nil
}
func (p *pausedPasswordVerifier) Dummy(context.Context, string) error { return nil }

type identityTestAuthorizer struct{}

func (identityTestAuthorizer) Allows(identitymodels.IdentityPrincipal, identitymodels.IdentityPermission) bool {
	return false
}
func TestLoginRechecksCredentialsAfterPasswordVerification(t *testing.T) {
	_, repository := identityFixture(t)
	actor := registerIdentityUser(t, repository, "login-race@example.test")
	snapshot, err := repository.CredentialsByEmail(t.Context(), actor.Email)
	if err != nil {
		t.Fatal(err)
	}
	passwords := &pausedPasswordVerifier{verified: make(chan struct{}), release: make(chan struct{})}
	service := identityservices.NewIdentityService(repository, passwords, identityTestAuthorizer{}, time.Now, uuid.NewString)
	result := make(chan error, 1)
	go func() {
		_, err := service.Login(t.Context(), actor.Email, "old password accepted by test verifier")
		result <- err
	}()
	<-passwords.verified
	if err := repository.ChangePassword(t.Context(), actor, snapshot, "new-hash", time.Now()); err != nil {
		close(passwords.release)
		t.Fatal(err)
	}
	close(passwords.release)
	if err := <-result; !errors.Is(err, identitymodels.ErrCredentials) {
		t.Fatalf("login using verified stale password: %v", err)
	}
}
