package datasources

import (
	"context"
	"errors"
	"slices"
	"sort"
	"time"

	identityrecords "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/table"
	jet "github.com/go-jet/jet/v2/postgres"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type identityQueryer interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func scanIdentity(row pgx.Row, extra ...any) (identityrecords.IdentityRecord, error) {
	var r identityrecords.IdentityRecord
	var claims []string
	fields := []any{&r.Account.ID, &r.Account.Name, &r.User.ID, &r.User.Email, &r.User.PasswordHash, &r.User.CredentialRevision, &r.User.MustChangePassword, &r.Membership.Role, &r.Membership.Enabled, &r.User.SystemRole, &r.User.PersonalAccountID, &r.Membership.IsOwner, &claims}
	err := row.Scan(append(fields, extra...)...)
	r.Membership.Claims = claims
	r.Membership.AccountID = r.Account.ID
	r.Membership.UserID = r.User.ID
	return r, err
}
func identitySelect() jet.SelectStatement {
	a, u, m := table.Accounts.FromSchema(""), table.Users.FromSchema(""), table.Memberships.FromSchema("")
	return jet.SELECT(a.ID, a.Name, u.ID, u.Email, u.PasswordHash, u.CredentialRevision, u.MustChangePassword, m.Role, m.Enabled, u.SystemRole, u.PersonalAccountID, m.IsOwner, m.Claims).FROM(a.INNER_JOIN(m, m.AccountID.EQ(a.ID)).INNER_JOIN(u, u.ID.EQ(m.UserID)))
}
func readIdentity(ctx context.Context, q identityQueryer, account, user uuid.UUID) (identityrecords.IdentityRecord, error) {
	m := table.Memberships.FromSchema("")
	sql, args := identitySelect().WHERE(m.AccountID.EQ(jet.UUID(account)).AND(m.UserID.EQ(jet.UUID(user)))).Sql()
	return scanIdentity(q.QueryRow(ctx, sql, args...))
}
func (source *IdentityDataSource) IdentityCredentials(ctx context.Context, email string) (identityrecords.IdentityRecord, error) {
	u := table.Users.FromSchema("")
	m := table.Memberships.FromSchema("")
	sql, args := identitySelect().WHERE(u.Email.EQ(jet.String(email)).AND(m.AccountID.EQ(u.PersonalAccountID))).Sql()
	return scanIdentity(source.database.QueryRow(ctx, sql, args...))
}
func execIdentity(ctx context.Context, tx pgx.Tx, statement jet.Statement) error {
	sql, args := statement.Sql()
	_, err := tx.Exec(ctx, sql, args...)
	return err
}
func identityDatabaseError(err error) error {
	var db *pgconn.PgError
	if errors.As(err, &db) && db.Code == "23505" {
		return identityrecords.ErrIdentityConflict
	}
	return err
}
func (source *IdentityDataSource) RegisterIdentity(ctx context.Context, r identityrecords.IdentityRecord) (identityrecords.IdentityRecord, error) {
	err := pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		eligible, err := lockSetup(ctx, tx)
		if err != nil {
			return err
		}
		if eligible != r.ExpectedSetupEligible {
			return identityrecords.ErrIdentityStaleFacts
		}
		if r.ConsumeSetup {
			if err := consumeSetup(ctx, tx); err != nil {
				return err
			}
		}
		a, u, m := table.Accounts.FromSchema(""), table.Users.FromSchema(""), table.Memberships.FromSchema("")
		for _, statement := range []jet.Statement{a.INSERT(a.AllColumns).MODEL(r.Account), u.INSERT(u.AllColumns).MODEL(r.User), m.INSERT(m.AllColumns).MODEL(r.Membership)} {
			if err := execIdentity(ctx, tx, statement); err != nil {
				return err
			}
		}
		r.Session, err = insertSession(ctx, tx, r.Session)
		return err
	})
	return r, identityDatabaseError(err)
}
func lockIdentityRows(ctx context.Context, tx pgx.Tx, account uuid.UUID, ids ...uuid.UUID) error {
	a, u, m := table.Accounts.FromSchema(""), table.Users.FromSchema(""), table.Memberships.FromSchema("")
	sql, args := jet.SELECT(a.ID).FROM(a).WHERE(a.ID.EQ(jet.UUID(account))).FOR(jet.UPDATE()).Sql()
	var id uuid.UUID
	if err := tx.QueryRow(ctx, sql, args...).Scan(&id); err != nil {
		return err
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i].String() < ids[j].String() })
	for i, user := range ids {
		if i > 0 && user == ids[i-1] {
			continue
		}
		sql, args = jet.SELECT(u.ID).FROM(u).WHERE(u.ID.EQ(jet.UUID(user))).FOR(jet.UPDATE()).Sql()
		if err := tx.QueryRow(ctx, sql, args...).Scan(&id); err != nil {
			return err
		}
	}
	for i, user := range ids {
		if i > 0 && user == ids[i-1] {
			continue
		}
		sql, args = jet.SELECT(m.UserID).FROM(m).WHERE(m.AccountID.EQ(jet.UUID(account)).AND(m.UserID.EQ(jet.UUID(user)))).FOR(jet.UPDATE()).Sql()
		if err := tx.QueryRow(ctx, sql, args...).Scan(&id); err != nil {
			return err
		}
	}
	return nil
}
func insertSession(ctx context.Context, tx pgx.Tx, r model.Sessions) (model.Sessions, error) {
	s := table.Sessions.FromSchema("")
	sql, args := s.INSERT(s.AllColumns).MODEL(r).RETURNING(s.AllColumns).Sql()
	return scanIdentitySession(tx.QueryRow(ctx, sql, args...))
}
func (source *IdentityDataSource) CreateIdentitySession(ctx context.Context, snapshot identityrecords.IdentityRecord, session model.Sessions) (identityrecords.IdentityRecord, error) {
	var result identityrecords.IdentityRecord
	err := pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if err := lockIdentityRows(ctx, tx, snapshot.Account.ID, snapshot.User.ID); err != nil {
			return err
		}
		current, err := readIdentity(ctx, tx, snapshot.Account.ID, snapshot.User.ID)
		if err != nil {
			return err
		}
		if current.Membership.Enabled != snapshot.Membership.Enabled || current.User.PasswordHash != snapshot.User.PasswordHash || current.User.CredentialRevision != snapshot.User.CredentialRevision {
			return identityrecords.ErrIdentityCredentials
		}
		current.Session, err = insertSession(ctx, tx, session)
		if err != nil {
			return err
		}
		result = current
		return nil
	})
	return result, err
}
func readSession(ctx context.Context, q identityQueryer, digest string, lock bool) (model.Sessions, error) {
	s := table.Sessions.FromSchema("")
	statement := jet.SELECT(s.AllColumns).FROM(s).WHERE(s.Digest.EQ(jet.String(digest)))
	if lock {
		statement = statement.FOR(jet.UPDATE())
	}
	sql, args := statement.Sql()
	return scanIdentitySession(q.QueryRow(ctx, sql, args...))
}
func scanIdentitySession(row pgx.Row) (model.Sessions, error) {
	var r model.Sessions
	err := row.Scan(&r.Digest, &r.AccountID, &r.UserID, &r.CredentialRevision, &r.ExpiresAt, &r.CreatedAt)
	return r, err
}
func (source *IdentityDataSource) compareActingSession(ctx context.Context, tx pgx.Tx, actor identityrecords.IdentityRecord) (identityrecords.IdentityRecord, error) {
	current, err := readIdentity(ctx, tx, actor.Account.ID, actor.User.ID)
	if err != nil {
		return identityrecords.IdentityRecord{}, err
	}
	session, err := readSession(ctx, tx, actor.Session.Digest, true)
	if errors.Is(err, pgx.ErrNoRows) {
		return identityrecords.IdentityRecord{}, identityrecords.ErrIdentityUnauthorized
	}
	if err != nil {
		return identityrecords.IdentityRecord{}, err
	}
	var now time.Time
	if err := tx.QueryRow(ctx, "SELECT clock_timestamp()").Scan(&now); err != nil {
		return identityrecords.IdentityRecord{}, err
	}
	if (session.ExpiresAt != nil && !session.ExpiresAt.After(now)) || session.UserID != actor.User.ID || session.AccountID != actor.Account.ID || session.CredentialRevision != current.User.CredentialRevision || actor.User.CredentialRevision != current.User.CredentialRevision || !current.Membership.Enabled {
		return identityrecords.IdentityRecord{}, identityrecords.ErrIdentityUnauthorized
	}
	if !identityAuthorityMatches(current, actor) {
		return identityrecords.IdentityRecord{}, identityrecords.ErrIdentityStaleFacts
	}
	if (session.ExpiresAt == nil) != (actor.Session.ExpiresAt == nil) || session.ExpiresAt != nil && !session.ExpiresAt.Equal(*actor.Session.ExpiresAt) {
		return identityrecords.IdentityRecord{}, identityrecords.ErrIdentityStaleFacts
	}
	current.Session = session
	return current, nil
}
func (source *IdentityDataSource) LogoutIdentity(ctx context.Context, actor identityrecords.IdentityRecord) error {
	return pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if err := lockIdentityRows(ctx, tx, actor.Account.ID, actor.User.ID); err != nil {
			return err
		}
		s := table.Sessions.FromSchema("")
		return execIdentity(ctx, tx, s.DELETE().WHERE(s.Digest.EQ(jet.String(actor.Session.Digest)).AND(s.UserID.EQ(jet.UUID(actor.User.ID)))))
	})
}
func (source *IdentityDataSource) ChangeIdentityPassword(ctx context.Context, actor, snapshot identityrecords.IdentityRecord, hash string) error {
	return pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if err := lockIdentityRows(ctx, tx, actor.Account.ID, actor.User.ID); err != nil {
			return err
		}
		current, err := source.compareActingSession(ctx, tx, actor)
		if err != nil {
			return err
		}
		if current.User.CredentialRevision != snapshot.User.CredentialRevision || current.User.PasswordHash != snapshot.User.PasswordHash {
			return identityrecords.ErrIdentityUnauthorized
		}
		u, s := table.Users.FromSchema(""), table.Sessions.FromSchema("")
		if err := execIdentity(ctx, tx, u.UPDATE(u.PasswordHash, u.CredentialRevision, u.MustChangePassword).SET(jet.String(hash), jet.Int64(current.User.CredentialRevision+1), jet.Bool(false)).WHERE(u.ID.EQ(jet.UUID(actor.User.ID)))); err != nil {
			return err
		}
		return execIdentity(ctx, tx, s.DELETE().WHERE(s.UserID.EQ(jet.UUID(actor.User.ID))))
	})
}
func (source *IdentityDataSource) CreateIdentityMember(ctx context.Context, actor, member identityrecords.IdentityRecord) (identityrecords.IdentityRecord, error) {
	err := pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if _, err := lockSetup(ctx, tx); err != nil {
			return err
		}
		if err := lockIdentityRows(ctx, tx, actor.Account.ID, actor.User.ID); err != nil {
			return err
		}
		_, err := source.compareActingSession(ctx, tx, actor)
		if err != nil {
			return err
		}
		a, u, m := table.Accounts.FromSchema(""), table.Users.FromSchema(""), table.Memberships.FromSchema("")
		personal := member.Account
		if err := execIdentity(ctx, tx, a.INSERT(a.AllColumns).MODEL(personal)); err != nil {
			return err
		}
		if err := execIdentity(ctx, tx, u.INSERT(u.AllColumns).MODEL(member.User)); err != nil {
			return err
		}
		owned := member.PersonalMembership
		if err := execIdentity(ctx, tx, m.INSERT(m.AllColumns).MODEL(owned)); err != nil {
			return err
		}
		return execIdentity(ctx, tx, m.INSERT(m.AllColumns).MODEL(member.Membership))
	})
	return member, identityDatabaseError(err)
}
func (source *IdentityDataSource) UpdateIdentityMember(ctx context.Context, actor, expected identityrecords.IdentityRecord, role string, claims []string, enabled bool) (identityrecords.IdentityRecord, error) {
	target := expected.User.ID
	var result identityrecords.IdentityRecord
	err := pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if err := lockIdentityRows(ctx, tx, actor.Account.ID, actor.User.ID, target); errors.Is(err, pgx.ErrNoRows) {
			return identityrecords.ErrIdentityNotFound
		} else if err != nil {
			return err
		}
		_, err := source.compareActingSession(ctx, tx, actor)
		if err != nil {
			return err
		}
		current, err := readIdentity(ctx, tx, actor.Account.ID, target)
		if err != nil {
			return err
		}
		m, s := table.Memberships.FromSchema(""), table.Sessions.FromSchema("")
		if current.Membership.IsOwner != expected.Membership.IsOwner || current.Membership.Role != expected.Membership.Role || current.Membership.Enabled != expected.Membership.Enabled || !slices.Equal(current.Membership.Claims, expected.Membership.Claims) || current.User.MustChangePassword != expected.User.MustChangePassword || current.User.Email != expected.User.Email {
			return identityrecords.ErrIdentityStaleFacts
		}
		current.Membership.Role, current.Membership.Claims, current.Membership.Enabled = role, claims, enabled
		if err := execIdentity(ctx, tx, m.UPDATE(m.Role, m.Claims, m.Enabled).MODEL(current.Membership).WHERE(m.AccountID.EQ(jet.UUID(actor.Account.ID)).AND(m.UserID.EQ(jet.UUID(target))))); err != nil {
			return err
		}
		if err := execIdentity(ctx, tx, s.DELETE().WHERE(s.AccountID.EQ(jet.UUID(actor.Account.ID)).AND(s.UserID.EQ(jet.UUID(target))))); err != nil {
			return err
		}
		current.Membership.Role = role
		current.Membership.Enabled = enabled
		result = current
		return nil
	})
	return result, err
}
func (source *IdentityDataSource) ListIdentityMembers(ctx context.Context, actor identityrecords.IdentityRecord, limit, offset int) (identityrecords.IdentityMemberRecords, error) {
	result := identityrecords.IdentityMemberRecords{Items: make([]identityrecords.IdentityRecord, 0)}
	err := source.identityReadTransaction(ctx, func(tx pgx.Tx) error {
		m, u := table.Memberships.FromSchema(""), table.Users.FromSchema("")
		sql, args := jet.SELECT(jet.COUNT(m.UserID)).FROM(m).WHERE(m.AccountID.EQ(jet.UUID(actor.Account.ID))).Sql()
		if err := tx.QueryRow(ctx, sql, args...).Scan(&result.Total); err != nil {
			return err
		}
		sql, args = identitySelect().WHERE(m.AccountID.EQ(jet.UUID(actor.Account.ID))).ORDER_BY(u.ID.ASC()).LIMIT(int64(limit)).OFFSET(int64(offset)).Sql()
		rows, err := tx.Query(ctx, sql, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			record, err := scanIdentity(rows)
			if err != nil {
				return err
			}
			result.Items = append(result.Items, record)
		}
		return rows.Err()
	})
	return result, err
}
func (source *IdentityDataSource) CleanupIdentitySessions(ctx context.Context, now time.Time) error {
	return pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		sessions := table.Sessions.FromSchema("")
		expired := jet.SELECT(sessions.Digest).FROM(sessions).
			WHERE(sessions.ExpiresAt.LT_EQ(jet.TimestampzT(now))).
			ORDER_BY(sessions.ExpiresAt.ASC()).LIMIT(200).FOR(jet.UPDATE().SKIP_LOCKED())
		return execIdentity(ctx, tx, sessions.DELETE().WHERE(sessions.Digest.IN(expired)))
	})
}
