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
)

func lockSetup(ctx context.Context, tx pgx.Tx) (bool, error) {
	t := table.IdentitySetup.FromSchema("")
	sql, args := jet.SELECT(t.BootstrapEligible).FROM(t).WHERE(t.ID.IS_TRUE()).FOR(jet.UPDATE()).Sql()
	var eligible bool
	err := tx.QueryRow(ctx, sql, args...).Scan(&eligible)
	return eligible, err
}
func consumeSetup(ctx context.Context, tx pgx.Tx) error {
	t := table.IdentitySetup.FromSchema("")
	return execIdentity(ctx, tx, t.UPDATE(t.BootstrapEligible).SET(jet.Bool(false)).WHERE(t.ID.IS_TRUE()))
}
func sortedIDs(ids []uuid.UUID) []uuid.UUID {
	ids = append([]uuid.UUID(nil), ids...)
	sort.Slice(ids, func(i, j int) bool { return ids[i].String() < ids[j].String() })
	result := make([]uuid.UUID, 0, len(ids))
	for _, id := range ids {
		if len(result) == 0 || result[len(result)-1] != id {
			result = append(result, id)
		}
	}
	return result
}
func lockAuthorityRows(ctx context.Context, tx pgx.Tx, accounts, users []uuid.UUID) error {
	a, u, m := table.Accounts.FromSchema(""), table.Users.FromSchema(""), table.Memberships.FromSchema("")
	accounts, users = sortedIDs(accounts), sortedIDs(users)
	var found uuid.UUID
	for _, id := range accounts {
		sql, args := jet.SELECT(a.ID).FROM(a).WHERE(a.ID.EQ(jet.UUID(id))).FOR(jet.UPDATE()).Sql()
		if err := tx.QueryRow(ctx, sql, args...).Scan(&found); err != nil {
			return err
		}
	}
	for _, id := range users {
		sql, args := jet.SELECT(u.ID).FROM(u).WHERE(u.ID.EQ(jet.UUID(id))).FOR(jet.UPDATE()).Sql()
		if err := tx.QueryRow(ctx, sql, args...).Scan(&found); err != nil {
			return err
		}
	}
	for _, account := range accounts {
		for _, user := range users {
			sql, args := jet.SELECT(m.UserID).FROM(m).WHERE(m.AccountID.EQ(jet.UUID(account)).AND(m.UserID.EQ(jet.UUID(user)))).FOR(jet.UPDATE()).Sql()
			if err := tx.QueryRow(ctx, sql, args...).Scan(&found); err != nil && !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
		}
	}
	return nil
}
func (source *IdentityDataSource) actorTransaction(ctx context.Context, actor identityrecords.IdentityRecord, fn func(pgx.Tx, identityrecords.IdentityRecord) error) error {
	return pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if err := lockIdentityRows(ctx, tx, actor.Account.ID, actor.User.ID); err != nil {
			return err
		}
		current, err := source.compareActingSession(ctx, tx, actor)
		if err != nil {
			return err
		}
		return fn(tx, current)
	})
}
func (source *IdentityDataSource) ListIdentityAccounts(ctx context.Context, actor identityrecords.IdentityRecord, limit, offset int) (identityrecords.IdentityMemberRecords, error) {
	result := identityrecords.IdentityMemberRecords{Items: []identityrecords.IdentityRecord{}}
	err := source.identityReadTransaction(ctx, func(tx pgx.Tx) error {
		m, a := table.Memberships.FromSchema(""), table.Accounts.FromSchema("")
		condition := m.UserID.EQ(jet.UUID(actor.User.ID)).AND(m.Enabled.IS_TRUE())
		sql, args := jet.SELECT(jet.COUNT(m.AccountID)).FROM(m).WHERE(condition).Sql()
		if err := tx.QueryRow(ctx, sql, args...).Scan(&result.Total); err != nil {
			return err
		}
		sql, args = identitySelect().WHERE(condition).ORDER_BY(a.ID.ASC()).LIMIT(int64(limit)).OFFSET(int64(offset)).Sql()
		rows, err := tx.Query(ctx, sql, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			r, err := scanIdentity(rows)
			if err != nil {
				return err
			}
			result.Items = append(result.Items, r)
		}
		return rows.Err()
	})
	return result, err
}
func (source *IdentityDataSource) SwitchIdentityAccount(ctx context.Context, actor, expected identityrecords.IdentityRecord, replacement model.Sessions) (identityrecords.IdentityRecord, error) {
	account := expected.Account.ID
	var result identityrecords.IdentityRecord
	err := pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if err := lockAuthorityRows(ctx, tx, []uuid.UUID{actor.Account.ID, account}, []uuid.UUID{actor.User.ID}); err != nil {
			return err
		}
		_, err := source.compareActingSession(ctx, tx, actor)
		if err != nil {
			return err
		}
		destination, err := readIdentity(ctx, tx, account, actor.User.ID)
		if err != nil {
			return err
		}
		if !identityAuthorityMatches(destination, expected) {
			return identityrecords.ErrIdentityStaleFacts
		}
		destination.Session, err = insertSession(ctx, tx, replacement)
		if err != nil {
			return err
		}
		s := table.Sessions.FromSchema("")
		if err := execIdentity(ctx, tx, s.DELETE().WHERE(s.Digest.EQ(jet.String(actor.Session.Digest)))); err != nil {
			return err
		}
		result = destination
		return nil
	})
	return result, err
}
func scanInvitation(row pgx.Row) (model.Invitations, error) {
	var r model.Invitations
	var claims []string
	err := row.Scan(&r.ID, &r.AccountID, &r.IssuerID, &r.Email, &r.Role, &claims, &r.Digest, &r.CreatedAt, &r.ExpiresAt, &r.AcceptedAt, &r.RevokedAt)
	r.Claims = claims
	return r, err
}
func readInvitation(ctx context.Context, q identityQueryer, condition jet.BoolExpression, lock bool) (model.Invitations, error) {
	t := table.Invitations.FromSchema("")
	statement := jet.SELECT(t.AllColumns).FROM(t).WHERE(condition)
	if lock {
		statement = statement.FOR(jet.UPDATE())
	}
	sql, args := statement.Sql()
	return scanInvitation(q.QueryRow(ctx, sql, args...))
}
func (source *IdentityDataSource) CreateIdentityInvitation(ctx context.Context, actor identityrecords.IdentityRecord, invitation model.Invitations) (model.Invitations, error) {
	err := source.actorTransaction(ctx, actor, func(tx pgx.Tx, _ identityrecords.IdentityRecord) error {
		t := table.Invitations.FromSchema("")
		return execIdentity(ctx, tx, t.INSERT(t.AllColumns).MODEL(invitation))
	})
	return invitation, identityDatabaseError(err)
}
func (source *IdentityDataSource) ListIdentityInvitations(ctx context.Context, actor identityrecords.IdentityRecord, limit, offset int) (identityrecords.IdentityInvitationRecords, error) {
	result := identityrecords.IdentityInvitationRecords{Items: []model.Invitations{}}
	err := source.identityReadTransaction(ctx, func(tx pgx.Tx) error {
		t := table.Invitations.FromSchema("")
		condition := t.AccountID.EQ(jet.UUID(actor.Account.ID))
		sql, args := jet.SELECT(jet.COUNT(t.ID)).FROM(t).WHERE(condition).Sql()
		if err := tx.QueryRow(ctx, sql, args...).Scan(&result.Total); err != nil {
			return err
		}
		sql, args = jet.SELECT(t.AllColumns).FROM(t).WHERE(condition).ORDER_BY(t.CreatedAt.DESC(), t.ID.DESC()).LIMIT(int64(limit)).OFFSET(int64(offset)).Sql()
		rows, err := tx.Query(ctx, sql, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			r, err := scanInvitation(rows)
			if err != nil {
				return err
			}
			result.Items = append(result.Items, r)
		}
		return rows.Err()
	})
	return result, err
}
func (source *IdentityDataSource) RevokeIdentityInvitation(ctx context.Context, actor identityrecords.IdentityRecord, expected model.Invitations, revokedAt time.Time) error {
	return source.actorTransaction(ctx, actor, func(tx pgx.Tx, _ identityrecords.IdentityRecord) error {
		t := table.Invitations.FromSchema("")
		condition := t.ID.EQ(jet.UUID(expected.ID)).AND(t.AccountID.EQ(jet.UUID(actor.Account.ID)))
		r, err := readInvitation(ctx, tx, condition, true)
		if err != nil {
			return err
		}
		if !identityOptionalTimeMatches(r.AcceptedAt, expected.AcceptedAt) || !identityOptionalTimeMatches(r.RevokedAt, expected.RevokedAt) {
			return identityrecords.ErrIdentityStaleFacts
		}
		return execIdentity(ctx, tx, t.UPDATE(t.RevokedAt).SET(jet.TimestampzT(revokedAt)).WHERE(condition))
	})
}
func (source *IdentityDataSource) AcceptIdentityInvitation(ctx context.Context, actor identityrecords.IdentityRecord, expected identityrecords.IdentityInvitationFactsRecord) (identityrecords.IdentityRecord, error) {
	t := table.Invitations.FromSchema("")
	snapshot := expected.Invitation
	condition := t.Digest.EQ(jet.String(snapshot.Digest))
	var result identityrecords.IdentityRecord
	err := pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if err := lockAuthorityRows(ctx, tx, []uuid.UUID{actor.Account.ID, snapshot.AccountID}, []uuid.UUID{actor.User.ID, snapshot.IssuerID}); err != nil {
			return err
		}
		_, err := source.compareActingSession(ctx, tx, actor)
		if err != nil {
			return err
		}
		invitation, err := readInvitation(ctx, tx, condition, true)
		if err != nil {
			return err
		}
		var now time.Time
		if err := tx.QueryRow(ctx, "SELECT clock_timestamp()").Scan(&now); err != nil {
			return err
		}
		if invitation.AccountID != snapshot.AccountID || invitation.IssuerID != snapshot.IssuerID || invitation.Email != snapshot.Email || invitation.Role != snapshot.Role || !slices.Equal(invitation.Claims, snapshot.Claims) || !invitation.ExpiresAt.Equal(snapshot.ExpiresAt) || invitation.AcceptedAt != nil || invitation.RevokedAt != nil || !invitation.ExpiresAt.After(now) {
			return identityrecords.ErrIdentityNotFound
		}
		issuer, err := readIdentity(ctx, tx, invitation.AccountID, invitation.IssuerID)
		if err != nil {
			return err
		}
		membership := model.Memberships{AccountID: invitation.AccountID, UserID: actor.User.ID, Role: invitation.Role, Claims: invitation.Claims, Enabled: true}
		if !identityAuthorityMatches(issuer, expected.Issuer) {
			return identityrecords.ErrIdentityStaleFacts
		}
		if _, err := readIdentity(ctx, tx, invitation.AccountID, actor.User.ID); err == nil {
			return identityrecords.ErrIdentityNotFound
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		m := table.Memberships.FromSchema("")
		if err := execIdentity(ctx, tx, m.INSERT(m.AllColumns).MODEL(membership)); err != nil {
			return err
		}
		if err := execIdentity(ctx, tx, t.UPDATE(t.AcceptedAt).SET(jet.TimestampzT(now)).WHERE(condition)); err != nil {
			return err
		}
		result, err = readIdentity(ctx, tx, invitation.AccountID, actor.User.ID)
		return err
	})
	return result, err
}
func scanSystemUser(row pgx.Row) (model.Users, error) {
	var r model.Users
	err := row.Scan(&r.ID, &r.Email, &r.SystemRole, &r.CreatedAt)
	return r, err
}
func (source *IdentityDataSource) ListIdentitySystemUsers(ctx context.Context, actor identityrecords.IdentityRecord, limit, offset int) (identityrecords.IdentityUserRecords, error) {
	result := identityrecords.IdentityUserRecords{Items: []model.Users{}}
	err := source.identityReadTransaction(ctx, func(tx pgx.Tx) error {
		u := table.Users.FromSchema("")
		sql, args := jet.SELECT(jet.COUNT(u.ID)).FROM(u).Sql()
		if err := tx.QueryRow(ctx, sql, args...).Scan(&result.Total); err != nil {
			return err
		}
		sql, args = jet.SELECT(jet.COUNT(u.ID)).FROM(u).WHERE(u.SystemRole.EQ(jet.String("admin"))).Sql()
		if err := tx.QueryRow(ctx, sql, args...).Scan(&result.AdminCount); err != nil {
			return err
		}
		sql, args = jet.SELECT(u.ID, u.Email, u.SystemRole, u.CreatedAt).FROM(u).ORDER_BY(u.ID.ASC()).LIMIT(int64(limit)).OFFSET(int64(offset)).Sql()
		rows, err := tx.Query(ctx, sql, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			r, err := scanSystemUser(rows)
			if err != nil {
				return err
			}
			result.Items = append(result.Items, r)
		}
		return rows.Err()
	})
	return result, err
}
func (source *IdentityDataSource) UpdateIdentitySystemUser(ctx context.Context, actor identityrecords.IdentityRecord, expected identityrecords.IdentitySystemUserFactsRecord, role string) (model.Users, error) {
	target := expected.Target.ID
	var result model.Users
	err := pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if _, err := lockSetup(ctx, tx); err != nil {
			return err
		}
		if err := lockAuthorityRows(ctx, tx, []uuid.UUID{actor.Account.ID}, []uuid.UUID{actor.User.ID, target}); err != nil {
			return err
		}
		if _, err := source.compareActingSession(ctx, tx, actor); err != nil {
			return err
		}
		u, s := table.Users.FromSchema(""), table.Sessions.FromSchema("")
		sql, args := jet.SELECT(u.ID, u.Email, u.SystemRole, u.CreatedAt).FROM(u).WHERE(u.ID.EQ(jet.UUID(target))).Sql()
		current, err := scanSystemUser(tx.QueryRow(ctx, sql, args...))
		if err != nil {
			return err
		}
		facts, err := readInstallationFacts(ctx, tx)
		if err != nil {
			return err
		}
		if current.SystemRole != expected.Target.SystemRole || !identityInstallationMatches(facts, expected.Installation) {
			return identityrecords.ErrIdentityStaleFacts
		}
		if err := execIdentity(ctx, tx, u.UPDATE(u.SystemRole).SET(jet.String(role)).WHERE(u.ID.EQ(jet.UUID(target)))); err != nil {
			return err
		}
		if err := execIdentity(ctx, tx, s.DELETE().WHERE(s.UserID.EQ(jet.UUID(target)))); err != nil {
			return err
		}
		current.SystemRole = role
		result = current
		return nil
	})
	return result, err
}
func (source *IdentityDataSource) BootstrapAdministrator(ctx context.Context, expected identityrecords.IdentitySystemUserFactsRecord) error {
	target := expected.Target.ID
	return pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout = '5s'"); err != nil {
			return err
		}
		if _, err := lockSetup(ctx, tx); err != nil {
			return err
		}
		u := table.Users.FromSchema("")
		facts, err := readInstallationFacts(ctx, tx)
		if err != nil {
			return err
		}
		if !identityInstallationMatches(facts, expected.Installation) {
			return identityrecords.ErrIdentityStaleFacts
		}
		if err := lockAuthorityRows(ctx, tx, nil, []uuid.UUID{target}); err != nil {
			return err
		}
		if err := execIdentity(ctx, tx, u.UPDATE(u.SystemRole).SET(jet.String("admin")).WHERE(u.ID.EQ(jet.UUID(target)))); err != nil {
			return err
		}
		s := table.Sessions.FromSchema("")
		if err := execIdentity(ctx, tx, s.DELETE().WHERE(s.UserID.EQ(jet.UUID(target)))); err != nil {
			return err
		}
		return consumeSetup(ctx, tx)
	})
}
