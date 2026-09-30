package datasources

import (
	"context"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/google/uuid"
)

func (s *IdentityDataSource) IdentitySessionAuthority(ctx context.Context, digest string) (r.IdentityRecord, time.Time, error) {
	var observed time.Time
	var sessionAccount, sessionUser uuid.UUID
	var revision int64
	var expires *time.Time
	record, err := scanIdentity(s.database.QueryRow(ctx, `SELECT a.id,a.name,u.id,u.email,u.password_hash,u.credential_revision,u.must_change_password,m.role,m.enabled,u.system_role,u.personal_account_id,m.is_owner,m.claims,
 s.account_id,s.user_id,s.credential_revision,s.expires_at,statement_timestamp()
 FROM sessions s JOIN users u ON u.id=s.user_id JOIN memberships m ON m.user_id=s.user_id AND m.account_id=s.account_id JOIN accounts a ON a.id=m.account_id
 WHERE s.digest=$1`, digest), &sessionAccount, &sessionUser, &revision, &expires, &observed)
	record.Session.Digest, record.Session.AccountID, record.Session.UserID = digest, sessionAccount, sessionUser
	record.Session.CredentialRevision, record.Session.ExpiresAt = revision, expires
	return record, observed, err
}

func (s *IdentityDataSource) IdentityBackgroundAuthority(ctx context.Context, account, user uuid.UUID) (r.IdentityRecord, error) {
	return readIdentity(ctx, s.database, account, user)
}
