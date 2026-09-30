package datasources

import (
	"context"
	"errors"
	"slices"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/table"
	jet "github.com/go-jet/jet/v2/postgres"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func identityOptionalTimeMatches(current, expected *time.Time) bool {
	return current == nil && expected == nil || current != nil && expected != nil && current.Equal(*expected)
}

func (s *IdentityDataSource) IdentityInvitation(ctx context.Context, account, id uuid.UUID) (model.Invitations, error) {
	t := table.Invitations.FromSchema("")
	return readInvitation(ctx, s.database, t.ID.EQ(jet.UUID(id)).AND(t.AccountID.EQ(jet.UUID(account))), false)
}

func readInstallationFacts(ctx context.Context, q identityQueryer) (r.IdentityInstallationRecord, error) {
	var facts r.IdentityInstallationRecord
	err := q.QueryRow(ctx, `SELECT bootstrap_eligible,ARRAY(SELECT id::text FROM users WHERE system_role='admin' ORDER BY id) FROM identity_setup WHERE id`).Scan(&facts.BootstrapEligible, &facts.AdministratorIDs)
	return facts, err
}

func (s *IdentityDataSource) IdentityInstallationFacts(ctx context.Context) (r.IdentityInstallationRecord, error) {
	return readInstallationFacts(ctx, s.database)
}

func (s *IdentityDataSource) IdentityMemberFacts(ctx context.Context, account, user uuid.UUID) (r.IdentityRecord, error) {
	return readIdentity(ctx, s.database, account, user)
}

func (s *IdentityDataSource) IdentitySystemUserFacts(ctx context.Context, id uuid.UUID) (r.IdentitySystemUserFactsRecord, error) {
	var facts r.IdentitySystemUserFactsRecord
	err := pgx.BeginTxFunc(ctx, s.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		var err error
		facts.Installation, err = readInstallationFacts(ctx, tx)
		if err != nil {
			return err
		}
		facts.Target, err = scanSystemUser(tx.QueryRow(ctx, `SELECT id,email,system_role,created_at FROM users WHERE id=$1`, id))
		return err
	})
	return facts, err
}

func (s *IdentityDataSource) IdentityInvitationFacts(ctx context.Context, digest string, recipient uuid.UUID) (r.IdentityInvitationFactsRecord, error) {
	var facts r.IdentityInvitationFactsRecord
	err := pgx.BeginTxFunc(ctx, s.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		var err error
		facts.Invitation, err = readInvitation(ctx, tx, table.Invitations.FromSchema("").Digest.EQ(jet.String(digest)), false)
		if err != nil {
			return err
		}
		facts.Issuer, err = readIdentity(ctx, tx, facts.Invitation.AccountID, facts.Invitation.IssuerID)
		if errors.Is(err, pgx.ErrNoRows) {
			err = nil
		}
		if err != nil {
			return err
		}
		return tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM memberships WHERE account_id=$1 AND user_id=$2)`, facts.Invitation.AccountID, recipient).Scan(&facts.AlreadyMember)
	})
	return facts, err
}

func identityAuthorityMatches(current, expected r.IdentityRecord) bool {
	return current.Account.ID == expected.Account.ID && current.User.ID == expected.User.ID &&
		current.User.CredentialRevision == expected.User.CredentialRevision && current.User.MustChangePassword == expected.User.MustChangePassword &&
		current.User.SystemRole == expected.User.SystemRole && current.User.Email == expected.User.Email &&
		current.Membership.Enabled == expected.Membership.Enabled && current.Membership.Role == expected.Membership.Role &&
		current.Membership.IsOwner == expected.Membership.IsOwner && slices.Equal(current.Membership.Claims, expected.Membership.Claims)
}

func identityInstallationMatches(current, expected r.IdentityInstallationRecord) bool {
	return current.BootstrapEligible == expected.BootstrapEligible && slices.Equal(current.AdministratorIDs, expected.AdministratorIDs)
}
