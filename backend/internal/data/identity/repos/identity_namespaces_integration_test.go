//go:build integration

package repos

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func blockedTransaction(t *testing.T, pool *pgxpool.Pool, query string, args ...any) (pgx.Tx, int) {
	t.Helper()
	tx, err := pool.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = tx.Rollback(context.Background()) })
	if _, err := tx.Exec(t.Context(), query, args...); err != nil {
		t.Fatal(err)
	}
	var pid int
	if err := tx.QueryRow(t.Context(), "SELECT pg_backend_pid()").Scan(&pid); err != nil {
		t.Fatal(err)
	}
	return tx, pid
}
func waitForBlocked(t *testing.T, pool *pgxpool.Pool, pid, count int) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	ticker := time.NewTicker(5 * time.Millisecond)
	defer ticker.Stop()
	for {
		var blocked int
		if err := pool.QueryRow(ctx, `WITH RECURSIVE blocked(pid) AS (
            SELECT pid FROM pg_stat_activity WHERE $1=ANY(pg_blocking_pids(pid))
            UNION SELECT a.pid FROM pg_stat_activity a JOIN blocked b ON b.pid=ANY(pg_blocking_pids(a.pid))
        ) SELECT count(*) FROM blocked`, pid).Scan(&blocked); err != nil {
			t.Fatal(err)
		}
		if blocked >= count {
			return
		}
		select {
		case <-ctx.Done():
			t.Fatalf("only %d/%d requests reached the lock barrier", blocked, count)
		case <-ticker.C:
		}
	}
}
func newRegistration(email string) domain.IdentityRegistration {
	return domain.IdentityRegistration{AccountID: uuid.NewString(), UserID: uuid.NewString(), AccountName: "Personal library", Email: email, PasswordHash: "hash", CreatedAt: time.Now(), Session: identitySession()}
}
func freshPrincipal(t *testing.T, r *IdentityRepository, email string) domain.IdentityPrincipal {
	t.Helper()
	credentials, err := r.CredentialsByEmail(t.Context(), email)
	if err != nil {
		t.Fatal(err)
	}
	p, err := r.CreateSession(t.Context(), credentials, identitySession())
	if err != nil {
		t.Fatal(err)
	}
	return p
}
func invitationFor(t *testing.T, r *IdentityRepository, issuer domain.IdentityPrincipal, email string, role domain.IdentityRole, claims ...domain.IdentityPermission) domain.IdentityInvitation {
	t.Helper()
	issued, err := identityApplication(t, r).CreateInvitation(t.Context(), issuer, email, role, claims)
	if err != nil {
		t.Fatal(err)
	}
	inv := issued.Invitation
	inv.Digest = issued.Code
	return inv
}
func acceptAndSwitch(t *testing.T, r *IdentityRepository, issuer, recipient domain.IdentityPrincipal, role domain.IdentityRole, claims ...domain.IdentityPermission) domain.IdentityPrincipal {
	t.Helper()
	invite := invitationFor(t, r, issuer, recipient.Email, role, claims...)
	if _, err := identityApplication(t, r).AcceptInvitation(t.Context(), recipient, invite.Digest); err != nil {
		t.Fatal(err)
	}
	p, _, err := identitySwitchFixture(t, r, t.Context(), recipient, issuer.AccountID, identitySession())
	if err != nil {
		t.Fatal(err)
	}
	return p
}
func TestFirstAdministratorIsAtomicAndBootstrapDecisionRollsBack(t *testing.T) {
	pool, r := identityFixture(t)
	failed := newRegistration("failure@example.test")
	failed.Session.Digest = "invalid"
	if _, err := identityRegisterFixture(t.Context(), r, failed); err == nil {
		t.Fatal("expected session constraint failure after bootstrap decision")
	}
	var eligible bool
	var users int
	if err := pool.QueryRow(t.Context(), "SELECT bootstrap_eligible,(SELECT count(*) FROM users) FROM identity_setup").Scan(&eligible, &users); err != nil || !eligible || users != 0 {
		t.Fatalf("bootstrap rollback: eligible=%v users=%d error=%v", eligible, users, err)
	}
	tx, pid := blockedTransaction(t, pool, "SELECT id FROM identity_setup FOR UPDATE")
	results := make(chan domain.IdentityPrincipal, 2)
	failures := make(chan error, 2)
	for i := range 2 {
		go func(i int) {
			session, err := identityApplication(t, r).Register(t.Context(), "Personal library", fmt.Sprintf("first%d@example.test", i), "Fixture password 123!")
			results <- session.Identity
			failures <- err
		}(i)
	}
	waitForBlocked(t, pool, pid, 2)
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	admins := 0
	for range 2 {
		p := <-results
		if err := <-failures; err != nil {
			t.Fatal(err)
		}
		if p.SystemRole == domain.Admin {
			admins++
		}
		if !p.IsOwner {
			t.Fatal("new user lacks personal ownership")
		}
	}
	if admins != 1 {
		t.Fatalf("created %d initial administrators", admins)
	}
}
func TestConcurrentAdministratorSelfDemotionsRetainOneAdministrator(t *testing.T) {
	pool, r := identityFixture(t)
	first := registerIdentityUser(t, r, "first-admin@example.test")
	second := registerIdentityUser(t, r, "second-admin@example.test")
	if _, err := identityApplication(t, r).UpdateSystemUser(t.Context(), first, second.UserID, domain.Admin); err != nil {
		t.Fatal(err)
	}
	second = freshPrincipal(t, r, second.Email)
	tx, pid := blockedTransaction(t, pool, "SELECT id FROM identity_setup FOR UPDATE")
	results := make(chan error, 2)
	for _, actor := range []domain.IdentityPrincipal{first, second} {
		go func(p domain.IdentityPrincipal) {
			_, err := identityApplication(t, r).UpdateSystemUser(t.Context(), p, p.UserID, domain.User)
			results <- err
		}(actor)
	}
	waitForBlocked(t, pool, pid, 2)
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	a, b := <-results, <-results
	if (a == nil) == (b == nil) {
		t.Fatalf("expected one demotion, got %v/%v", a, b)
	}
	if a == nil {
		a = b
	}
	if !errors.Is(a, domain.ErrConflict) {
		t.Fatalf("last administrator: %v", a)
	}
	var count int
	if err := pool.QueryRow(t.Context(), "SELECT count(*) FROM users WHERE system_role='admin'").Scan(&count); err != nil || count != 1 {
		t.Fatalf("remaining admins=%d %v", count, err)
	}
}

func TestSystemAdministratorCountIncludesUsersOutsidePage(t *testing.T) {
	_, repository := identityFixture(t)
	first := registerIdentityUser(t, repository, "count-first@example.test")
	second := registerIdentityUser(t, repository, "count-second@example.test")
	if _, err := identityApplication(t, repository).UpdateSystemUser(t.Context(), first, second.UserID, domain.Admin); err != nil {
		t.Fatal(err)
	}
	for _, offset := range []int{0, 1, 2} {
		page, err := identityApplication(t, repository).ListSystemUsers(t.Context(), first, 1, offset)
		if err != nil {
			t.Fatal(err)
		}
		if page.Total != 2 || page.AdminCount != 2 || len(page.Items) > 1 || (offset < 2 && len(page.Items) != 1) {
			t.Fatalf("global administrator count at offset %d: %+v", offset, page)
		}
	}
	if _, err := identityApplication(t, repository).UpdateSystemUser(t.Context(), first, second.UserID, domain.User); err != nil {
		t.Fatal(err)
	}
	page, err := identityApplication(t, repository).ListSystemUsers(t.Context(), first, 1, 0)
	if err != nil || page.AdminCount != 1 {
		t.Fatalf("count after demotion: %+v, %v", page, err)
	}
	if _, err := identityApplication(t, repository).UpdateSystemUser(t.Context(), first, first.UserID, domain.User); !errors.Is(err, domain.ErrConflict) {
		t.Fatalf("final administrator demotion: %v", err)
	}
	second = freshPrincipal(t, repository, second.Email)
	if _, err := identityApplication(t, repository).ListSystemUsers(t.Context(), second, 1, 0); !errors.Is(err, domain.ErrForbidden) {
		t.Fatalf("non-administrator read installation count: %v", err)
	}
}

func TestPersistentSessionKeepsNoExpiryAcrossSwitchAndRemainsRevocable(t *testing.T) {
	_, repository := identityFixture(t)
	owner := registerIdentityUser(t, repository, "persistent-owner@example.test")
	registration := newRegistration("persistent-member@example.test")
	registration.Session.ExpiresAt = nil
	member, err := identityRegisterFixture(t.Context(), repository, registration)
	if err != nil {
		t.Fatal(err)
	}
	farFuture := time.Now().AddDate(50, 0, 0)
	current, err := identityAuthenticateFixture(t, repository, t.Context(), member.SessionDigest, farFuture)
	if err != nil || current.SessionExpiresAt != nil {
		t.Fatalf("persistent authentication: %+v %v", current, err)
	}
	if err := repository.CleanupSessions(t.Context(), farFuture); err != nil {
		t.Fatal(err)
	}
	if _, err := identityAuthenticateFixture(t, repository, t.Context(), member.SessionDigest, farFuture); err != nil {
		t.Fatalf("cleanup removed persistent session: %v", err)
	}
	owner = freshPrincipal(t, repository, owner.Email)
	invite := invitationFor(t, repository, owner, member.Email, domain.Viewer)
	if _, err := identityApplication(t, repository).AcceptInvitation(t.Context(), member, invite.Digest); err != nil {
		t.Fatal(err)
	}
	switched, expiry, err := identitySwitchFixture(t, repository, t.Context(), member, owner.AccountID, identitySession())
	if err != nil || expiry != nil || switched.SessionExpiresAt != nil {
		t.Fatalf("persistent switch: %+v %v %v", switched, expiry, err)
	}
	if _, err := identityAuthenticateFixture(t, repository, t.Context(), member.SessionDigest, time.Now()); !errors.Is(err, domain.ErrUnauthorized) {
		t.Fatalf("switch retained old token: %v", err)
	}
	if _, err := identityApplication(t, repository).ListAccounts(t.Context(), switched, 10, 0); err != nil {
		t.Fatalf("transaction rejected persistent session: %v", err)
	}
	if err := repository.Logout(t.Context(), switched); err != nil {
		t.Fatal(err)
	}
	if _, err := identityAuthenticateFixture(t, repository, t.Context(), switched.SessionDigest, time.Now()); !errors.Is(err, domain.ErrUnauthorized) {
		t.Fatalf("persistent logout failed: %v", err)
	}
}
func TestInvitationAcceptanceAndSwitchAreSingleUseWithFixedExpiry(t *testing.T) {
	pool, r := identityFixture(t)
	owner := registerIdentityUser(t, r, "invite-owner@example.test")
	recipient := registerIdentityUser(t, r, "recipient@example.test")
	wrong := registerIdentityUser(t, r, "wrong@example.test")
	invite := invitationFor(t, r, owner, recipient.Email, domain.Viewer, domain.DocumentsCreate)
	if _, err := identityApplication(t, r).AcceptInvitation(t.Context(), wrong, invite.Digest); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("wrong email: %v", err)
	}
	tx, pid := blockedTransaction(t, pool, "SELECT id FROM accounts WHERE id=$1 FOR UPDATE", owner.AccountID)
	accepted := make(chan error, 2)
	for range 2 {
		go func() {
			m, err := identityApplication(t, r).AcceptInvitation(t.Context(), recipient, invite.Digest)
			if err == nil && (m.Role != domain.Viewer || len(m.Claims) != 1 || m.Claims[0] != domain.DocumentsCreate) {
				err = fmt.Errorf("grant array failed round trip: %+v", m)
			}
			accepted <- err
		}()
	}
	waitForBlocked(t, pool, pid, 2)
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	a, b := <-accepted, <-accepted
	if (a == nil) == (b == nil) {
		t.Fatalf("acceptance winners %v/%v", a, b)
	}
	if a == nil {
		a = b
	}
	if !errors.Is(a, domain.ErrNotFound) {
		t.Fatalf("replay failure: %v", a)
	}
	var expiry time.Time
	if err := pool.QueryRow(t.Context(), "SELECT expires_at FROM sessions WHERE digest=$1", recipient.SessionDigest).Scan(&expiry); err != nil {
		t.Fatal(err)
	}
	tx, pid = blockedTransaction(t, pool, "SELECT id FROM accounts WHERE id=$1 FOR UPDATE", owner.AccountID)
	switched := make(chan error, 2)
	principals := make(chan domain.IdentityPrincipal, 2)
	for range 2 {
		go func() {
			p, actual, err := identitySwitchFixture(t, r, t.Context(), recipient, owner.AccountID, identitySession())
			if err == nil && !actual.Equal(expiry) {
				err = fmt.Errorf("expiry changed: %v != %v", actual, expiry)
			}
			principals <- p
			switched <- err
		}()
	}
	waitForBlocked(t, pool, pid, 2)
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	a, b = <-switched, <-switched
	p1, p2 := <-principals, <-principals
	if (a == nil) == (b == nil) {
		t.Fatalf("switch winners %v/%v", a, b)
	}
	if a == nil {
		a = b
	}
	if !errors.Is(a, domain.ErrUnauthorized) {
		t.Fatalf("old bearer survived: %v", a)
	}
	if _, err := identityAuthenticateFixture(t, r, t.Context(), recipient.SessionDigest, time.Now()); !errors.Is(err, domain.ErrUnauthorized) {
		t.Fatalf("old session still active: %v", err)
	}
	if p1.AccountID != owner.AccountID && p2.AccountID != owner.AccountID {
		t.Fatal("no switched principal")
	}
	personal := freshPrincipal(t, r, recipient.Email)
	if personal.AccountID != recipient.AccountID || !personal.IsOwner || len(personal.Claims) != 0 {
		t.Fatalf("personal login/empty grants: %+v", personal)
	}
}
func TestInvitationRechecksLockedIssuerAndWholeDelegatedRole(t *testing.T) {
	pool, r := identityFixture(t)
	owner := registerIdentityUser(t, r, "delegator@example.test")
	managerPersonal := registerIdentityUser(t, r, "manager@example.test")
	recipient := registerIdentityUser(t, r, "invitee@example.test")
	manager := acceptAndSwitch(t, r, owner, managerPersonal, domain.Viewer, domain.UsersManage)
	input := domain.IdentityInvitation{ID: uuid.NewString(), Email: recipient.Email, Role: domain.User, Digest: identitySession().Digest, CreatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)}
	if _, err := identityApplication(t, r).CreateInvitation(t.Context(), manager, input.Email, input.Role, input.Claims); !errors.Is(err, domain.ErrForbidden) {
		t.Fatalf("role-bundle escalation: %v", err)
	}
	invite := invitationFor(t, r, manager, recipient.Email, domain.Viewer)
	tx, pid := blockedTransaction(t, pool, "SELECT id FROM accounts WHERE id=$1 FOR UPDATE", owner.AccountID)
	if _, err := tx.Exec(t.Context(), "UPDATE memberships SET claims='{}' WHERE account_id=$1 AND user_id=$2", owner.AccountID, manager.UserID); err != nil {
		t.Fatal(err)
	}
	result := make(chan error, 1)
	go func() {
		_, err := identityApplication(t, r).AcceptInvitation(t.Context(), recipient, invite.Digest)
		result <- err
	}()
	waitForBlocked(t, pool, pid, 1)
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := <-result; !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("stale issuer delegated after wait: %v", err)
	}
	var accepted *time.Time
	if err := pool.QueryRow(t.Context(), "SELECT accepted_at FROM invitations WHERE id=$1", invite.ID).Scan(&accepted); err != nil || accepted != nil {
		t.Fatalf("failed acceptance consumed invitation: %v %v", accepted, err)
	}
}
func TestSystemMutationRechecksAdministratorAfterLockWait(t *testing.T) {
	pool, r := identityFixture(t)
	actor := registerIdentityUser(t, r, "stale-admin@example.test")
	target := registerIdentityUser(t, r, "ordinary@example.test")
	tx, pid := blockedTransaction(t, pool, "SELECT id FROM identity_setup FOR UPDATE")
	if _, err := tx.Exec(t.Context(), "UPDATE users SET system_role='user' WHERE id=$1", actor.UserID); err != nil {
		t.Fatal(err)
	}
	result := make(chan error, 1)
	go func() {
		_, err := identityApplication(t, r).UpdateSystemUser(t.Context(), actor, target.UserID, domain.Admin)
		result <- err
	}()
	waitForBlocked(t, pool, pid, 1)
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := <-result; !errors.Is(err, domain.ErrForbidden) {
		t.Fatalf("stale administrator promoted user: %v", err)
	}
}
func TestBootstrapRecoveryRequiresNoAdministratorAndRevokesSessions(t *testing.T) {
	pool, r := identityFixture(t)
	target := registerIdentityUser(t, r, "recover@example.test")
	source := identityApplication(t, r)
	id := target.UserID
	if err := source.BootstrapAdministrator(t.Context(), id); err == nil {
		t.Fatal("recovery replaced existing administrator")
	}
	if _, err := pool.Exec(t.Context(), "UPDATE users SET system_role='user'; UPDATE identity_setup SET bootstrap_eligible=true"); err != nil {
		t.Fatal(err)
	}
	if err := source.BootstrapAdministrator(t.Context(), id); err != nil {
		t.Fatal(err)
	}
	if _, err := identityAuthenticateFixture(t, r, t.Context(), target.SessionDigest, time.Now()); !errors.Is(err, domain.ErrUnauthorized) {
		t.Fatalf("recovery left old session: %v", err)
	}
	var eligible bool
	if err := pool.QueryRow(t.Context(), "SELECT bootstrap_eligible FROM identity_setup").Scan(&eligible); err != nil || eligible {
		t.Fatalf("recovery did not consume eligibility: %v %v", eligible, err)
	}
	if err := source.BootstrapAdministrator(t.Context(), uuid.NewString()); err == nil {
		t.Fatal("recovery ignored existing administrator")
	}
}
