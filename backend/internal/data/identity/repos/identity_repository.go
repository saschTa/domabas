package repos

import (
	"context"
	"errors"
	"time"

	identityrecords "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	identityinterfaces "github.com/domabas/domabas/backend/internal/domain/identity/interfaces"
	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type IdentityRepository struct{ source IdentitySource }

var _ identityinterfaces.IdentityRepository = (*IdentityRepository)(nil)

func NewIdentityRepository(source IdentitySource) *IdentityRepository {
	return &IdentityRepository{source: source}
}

func identityError(err error) error {
	switch {
	case errors.Is(err, identityrecords.ErrActivityUnavailable):
		return identitymodels.ErrActivityUnavailable
	case errors.Is(err, identityrecords.ErrIdentityStaleFacts):
		return identitymodels.ErrStaleFacts
	case errors.Is(err, identityrecords.ErrIdentityUnauthorized):
		return identitymodels.ErrUnauthorized
	case errors.Is(err, identityrecords.ErrIdentityPasswordChange):
		return identitymodels.ErrPasswordChange
	case errors.Is(err, identityrecords.ErrIdentityCredentials):
		return identitymodels.ErrCredentials
	case errors.Is(err, identityrecords.ErrIdentityForbidden):
		return identitymodels.ErrForbidden
	case errors.Is(err, identityrecords.ErrIdentityConflict):
		return identitymodels.ErrConflict
	case errors.Is(err, identityrecords.ErrIdentityNotFound), errors.Is(err, pgx.ErrNoRows):
		return identitymodels.ErrNotFound
	default:
		return err
	}
}
func (r *IdentityRepository) Register(ctx context.Context, input identitymodels.IdentityRegistration) (identitymodels.IdentityPrincipal, error) {
	account, err := uuid.Parse(input.AccountID)
	if err != nil {
		return identitymodels.IdentityPrincipal{}, err
	}
	user, err := uuid.Parse(input.UserID)
	if err != nil {
		return identitymodels.IdentityPrincipal{}, err
	}
	record, err := r.source.RegisterIdentity(ctx, identityrecords.IdentityRecord{ExpectedSetupEligible: input.ExpectedSetupEligible, ConsumeSetup: input.ConsumeSetup, Account: model.Accounts{ID: account, Name: input.AccountName, CreatedAt: input.CreatedAt}, User: model.Users{ID: user, Email: input.Email, PasswordHash: input.PasswordHash, CredentialRevision: 1, CreatedAt: input.CreatedAt, SystemRole: string(input.SystemRole), PersonalAccountID: account}, Membership: model.Memberships{AccountID: account, UserID: user, Role: "admin", Enabled: true, IsOwner: true, Claims: []string{}}, Session: model.Sessions{Digest: input.Session.Digest, AccountID: account, UserID: user, CredentialRevision: 1, ExpiresAt: input.Session.ExpiresAt, CreatedAt: input.Session.CreatedAt}})
	return identityPrincipalRecordToDomainMapper(record), identityError(err)
}
func (r *IdentityRepository) CredentialsByEmail(ctx context.Context, email string) (identitymodels.IdentityCredentials, error) {
	record, err := r.source.IdentityCredentials(ctx, email)
	return identitymodels.IdentityCredentials{Principal: identityPrincipalRecordToDomainMapper(record), PasswordHash: record.User.PasswordHash, Enabled: record.Membership.Enabled}, identityError(err)
}
func (r *IdentityRepository) CreateSession(ctx context.Context, snapshot identitymodels.IdentityCredentials, session identitymodels.IdentitySessionRecord) (identitymodels.IdentityPrincipal, error) {
	account, e1 := uuid.Parse(snapshot.Principal.AccountID)
	user, e2 := uuid.Parse(snapshot.Principal.UserID)
	if e1 != nil || e2 != nil {
		return identitymodels.IdentityPrincipal{}, identitymodels.ErrCredentials
	}
	record, err := r.source.CreateIdentitySession(ctx, identityrecords.IdentityRecord{Account: model.Accounts{ID: account}, User: model.Users{ID: user, PasswordHash: snapshot.PasswordHash, CredentialRevision: snapshot.Principal.CredentialRevision}, Membership: model.Memberships{Enabled: snapshot.Enabled}}, model.Sessions{Digest: session.Digest, AccountID: account, UserID: user, CredentialRevision: snapshot.Principal.CredentialRevision, CreatedAt: session.CreatedAt, ExpiresAt: session.ExpiresAt})
	return identityPrincipalRecordToDomainMapper(record), identityError(err)
}
func (r *IdentityRepository) Logout(ctx context.Context, p identitymodels.IdentityPrincipal) error {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return err
	}
	return identityError(r.source.LogoutIdentity(ctx, actor))
}
func (r *IdentityRepository) ChangePassword(ctx context.Context, p identitymodels.IdentityPrincipal, snapshot identitymodels.IdentityCredentials, hash string, _ time.Time) error {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return err
	}
	return identityError(r.source.ChangeIdentityPassword(ctx, actor, identityrecords.IdentityRecord{User: model.Users{PasswordHash: snapshot.PasswordHash, CredentialRevision: snapshot.Principal.CredentialRevision}}, hash))
}
func (r *IdentityRepository) CreateMember(ctx context.Context, p identitymodels.IdentityPrincipal, input identitymodels.IdentityNewMember, _ time.Time) (identitymodels.IdentityMember, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return identitymodels.IdentityMember{}, err
	}
	id, err := uuid.Parse(input.ID)
	if err != nil {
		return identitymodels.IdentityMember{}, err
	}
	account, err := uuid.Parse(input.AccountID)
	if err != nil {
		return identitymodels.IdentityMember{}, err
	}
	record, err := r.source.CreateIdentityMember(ctx, actor, identityrecords.IdentityRecord{Account: model.Accounts{ID: account, Name: input.PersonalAccountName, CreatedAt: input.CreatedAt}, PersonalMembership: model.Memberships{AccountID: account, UserID: id, Role: string(input.PersonalRole), Enabled: true, IsOwner: input.PersonalOwner, Claims: []string{}}, User: model.Users{ID: id, Email: input.Email, PasswordHash: input.PasswordHash, CredentialRevision: 1, MustChangePassword: true, CreatedAt: input.CreatedAt, SystemRole: "user", PersonalAccountID: account}, Membership: model.Memberships{AccountID: actor.Account.ID, UserID: id, Role: string(input.Role), Enabled: true, Claims: identityClaimStringsMapper(input.Claims)}})
	return identityMemberRecordToDomainMapper(record), identityError(err)
}
func (r *IdentityRepository) UpdateMember(ctx context.Context, p identitymodels.IdentityPrincipal, expected identitymodels.IdentityMember, role identitymodels.IdentityRole, claims []identitymodels.IdentityPermission, enabled bool, _ time.Time) (identitymodels.IdentityMember, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return identitymodels.IdentityMember{}, err
	}
	target, err := uuid.Parse(expected.ID)
	if err != nil {
		return identitymodels.IdentityMember{}, identitymodels.ErrNotFound
	}
	snapshot := identityrecords.IdentityRecord{User: model.Users{ID: target, Email: expected.Email, MustChangePassword: expected.MustChangePassword}, Membership: model.Memberships{AccountID: actor.Account.ID, UserID: target, Role: string(expected.Role), Claims: identityClaimStringsMapper(expected.Claims), Enabled: expected.Enabled, IsOwner: expected.IsOwner}}
	record, err := r.source.UpdateIdentityMember(ctx, actor, snapshot, string(role), identityClaimStringsMapper(claims), enabled)
	return identityMemberRecordToDomainMapper(record), identityError(err)
}
func (r *IdentityRepository) ListMembers(ctx context.Context, p identitymodels.IdentityPrincipal, limit, offset int, _ time.Time) (identitymodels.IdentityMemberPage, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return identitymodels.IdentityMemberPage{}, err
	}
	records, err := r.source.ListIdentityMembers(ctx, actor, limit, offset)
	if err != nil {
		return identitymodels.IdentityMemberPage{}, identityError(err)
	}
	result := identitymodels.IdentityMemberPage{Items: make([]identitymodels.IdentityMember, 0, len(records.Items)), Total: records.Total}
	for _, record := range records.Items {
		result.Items = append(result.Items, identityMemberRecordToDomainMapper(record))
	}
	return result, nil
}
func (r *IdentityRepository) CleanupSessions(ctx context.Context, now time.Time) error {
	return r.source.CleanupIdentitySessions(ctx, now)
}
