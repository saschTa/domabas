package repos

import (
	"context"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
)

func (r *IdentityRepository) ListAccounts(ctx context.Context, p domain.IdentityPrincipal, limit, offset int) (domain.IdentityMembershipPage, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return domain.IdentityMembershipPage{}, err
	}
	rows, err := r.source.ListIdentityAccounts(ctx, actor, limit, offset)
	result := domain.IdentityMembershipPage{Items: []domain.IdentityMembership{}, Total: rows.Total}
	for _, row := range rows.Items {
		result.Items = append(result.Items, identityMembershipRecordToDomainMapper(row))
	}
	return result, identityError(err)
}
func (r *IdentityRepository) SwitchAccount(ctx context.Context, p domain.IdentityPrincipal, expected domain.IdentityAuthorityFacts, session domain.IdentitySessionRecord) (domain.IdentityPrincipal, *time.Time, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return domain.IdentityPrincipal{}, nil, err
	}
	destination, err := identityBackgroundFactsMapper(expected)
	if err != nil {
		return domain.IdentityPrincipal{}, nil, domain.ErrNotFound
	}
	row, err := r.source.SwitchIdentityAccount(ctx, actor, destination, model.Sessions{Digest: session.Digest, AccountID: destination.Account.ID, UserID: actor.User.ID, CredentialRevision: actor.User.CredentialRevision, ExpiresAt: session.ExpiresAt, CreatedAt: session.CreatedAt})
	return identityPrincipalRecordToDomainMapper(row), row.Session.ExpiresAt, identityError(err)
}
func (r *IdentityRepository) CreateInvitation(ctx context.Context, p domain.IdentityPrincipal, input domain.IdentityInvitation) (domain.IdentityInvitation, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return domain.IdentityInvitation{}, err
	}
	id, err := uuid.Parse(input.ID)
	if err != nil {
		return domain.IdentityInvitation{}, err
	}
	row, err := r.source.CreateIdentityInvitation(ctx, actor, model.Invitations{ID: id, AccountID: actor.Account.ID, IssuerID: actor.User.ID, Email: input.Email, Role: string(input.Role), Claims: identityClaimStringsMapper(input.Claims), Digest: input.Digest, CreatedAt: input.CreatedAt, ExpiresAt: input.ExpiresAt})
	return identityInvitationRecordToDomainMapper(row), identityError(err)
}
func (r *IdentityRepository) ListInvitations(ctx context.Context, p domain.IdentityPrincipal, limit, offset int) (domain.IdentityInvitationPage, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return domain.IdentityInvitationPage{}, err
	}
	rows, err := r.source.ListIdentityInvitations(ctx, actor, limit, offset)
	result := domain.IdentityInvitationPage{Items: []domain.IdentityInvitation{}, Total: rows.Total}
	for _, row := range rows.Items {
		result.Items = append(result.Items, identityInvitationRecordToDomainMapper(row))
	}
	return result, identityError(err)
}
func (r *IdentityRepository) RevokeInvitation(ctx context.Context, p domain.IdentityPrincipal, expected domain.IdentityInvitation, revokedAt time.Time) error {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return err
	}
	invitation, err := uuid.Parse(expected.ID)
	if err != nil {
		return domain.ErrNotFound
	}
	return identityError(r.source.RevokeIdentityInvitation(ctx, actor, model.Invitations{ID: invitation, AccountID: actor.Account.ID, AcceptedAt: expected.AcceptedAt, RevokedAt: expected.RevokedAt}, revokedAt))
}
func (r *IdentityRepository) AcceptInvitation(ctx context.Context, p domain.IdentityPrincipal, facts domain.IdentityInvitationFacts) (domain.IdentityMembership, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return domain.IdentityMembership{}, err
	}
	expected, err := identityInvitationFactsMapper(facts)
	if err != nil {
		return domain.IdentityMembership{}, err
	}
	row, err := r.source.AcceptIdentityInvitation(ctx, actor, expected)
	return identityMembershipRecordToDomainMapper(row), identityError(err)
}
func (r *IdentityRepository) ListSystemUsers(ctx context.Context, p domain.IdentityPrincipal, limit, offset int) (domain.SystemUserPage, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return domain.SystemUserPage{}, err
	}
	rows, err := r.source.ListIdentitySystemUsers(ctx, actor, limit, offset)
	result := domain.SystemUserPage{Items: []domain.SystemUser{}, Total: rows.Total, AdminCount: rows.AdminCount}
	for _, row := range rows.Items {
		result.Items = append(result.Items, identitySystemUserRecordToDomainMapper(row))
	}
	return result, identityError(err)
}
func (r *IdentityRepository) UpdateSystemUser(ctx context.Context, p domain.IdentityPrincipal, facts domain.IdentitySystemUserFacts, role domain.IdentityRole) (domain.SystemUser, error) {
	actor, err := identityPrincipalDomainToRecordMapper(p)
	if err != nil {
		return domain.SystemUser{}, err
	}
	expected, err := identitySystemUserFactsMapper(facts)
	if err != nil {
		return domain.SystemUser{}, domain.ErrNotFound
	}
	row, err := r.source.UpdateIdentitySystemUser(ctx, actor, expected, string(role))
	return identitySystemUserRecordToDomainMapper(row), identityError(err)
}
