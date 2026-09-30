package datasources

import (
	"context"
	"errors"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	r "github.com/domabas/domabas/backend/internal/data/realtime/models"
	"github.com/jackc/pgx/v5"
)

type RealtimeAuthorityDataSource struct{ database *postgres.PostgresDatabase }

func NewRealtimeAuthorityDataSource(database *postgres.PostgresDatabase) *RealtimeAuthorityDataSource {
	return &RealtimeAuthorityDataSource{database: database}
}
func (s *RealtimeAuthorityDataSource) Snapshot(ctx context.Context, subject r.RealtimeSubject, accounts, users []string) (r.RealtimeSnapshot, error) {
	out := r.RealtimeSnapshot{Memberships: []r.RealtimeMembership{}, MemberUsers: map[string]bool{}}
	tx, err := s.database.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return out, err
	}
	defer func() {
		deadline := time.Now().Add(time.Second)
		if parent, ok := ctx.Deadline(); ok && parent.Before(deadline) {
			deadline = parent
		}
		cleanup, cancel := context.WithDeadline(context.Background(), deadline)
		defer cancel()
		_ = tx.Rollback(cleanup)
	}()
	facts := &out.Identity
	err = tx.QueryRow(ctx, `SELECT u.system_role,u.id::text,m.account_id::text,u.credential_revision,u.must_change_password,m.enabled,s.digest,s.user_id::text,s.account_id::text,s.credential_revision,s.expires_at,transaction_timestamp()
 FROM sessions s JOIN users u ON u.id=s.user_id JOIN memberships m ON m.user_id=u.id AND m.account_id=s.account_id JOIN accounts a ON a.id=m.account_id
 WHERE s.digest=$1 AND s.user_id=$2::uuid AND s.account_id=$3::uuid`, subject.SessionDigest, subject.UserID, subject.AccountID).Scan(&out.SystemRole, &facts.Principal.UserID, &facts.Principal.AccountID, &facts.Principal.CredentialRevision, &facts.Principal.MustChangePassword, &facts.MembershipEnabled, &facts.Principal.SessionDigest, &facts.SessionUserID, &facts.SessionAccountID, &facts.SessionCredentialRevision, &facts.Principal.SessionExpiresAt, &facts.ObservedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return out, nil
	}
	if err != nil {
		return out, err
	}
	rows, err := tx.Query(ctx, `SELECT m.account_id::text,m.role,m.is_owner,m.claims,m.enabled FROM memberships m JOIN accounts a ON a.id=m.account_id WHERE m.user_id=$1::uuid AND m.account_id=ANY($2::uuid[])`, subject.UserID, accounts)
	if err != nil {
		return out, err
	}
	for rows.Next() {
		var member r.RealtimeMembership
		if err = rows.Scan(&member.AccountID, &member.Role, &member.Owner, &member.Claims, &member.Enabled); err != nil {
			rows.Close()
			return out, err
		}
		out.Memberships = append(out.Memberships, member)
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return out, err
	}
	if len(users) > 0 {
		rows, err = tx.Query(ctx, `SELECT user_id::text FROM memberships WHERE account_id=$1::uuid AND user_id=ANY($2::uuid[])`, subject.AccountID, users)
		if err != nil {
			return out, err
		}
		for rows.Next() {
			var user string
			if err = rows.Scan(&user); err != nil {
				rows.Close()
				return out, err
			}
			out.MemberUsers[user] = true
		}
		rows.Close()
		if err = rows.Err(); err != nil {
			return out, err
		}
	}
	err = tx.Commit(ctx)
	return out, err
}
