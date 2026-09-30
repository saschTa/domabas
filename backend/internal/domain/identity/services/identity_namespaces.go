package services

import (
	"context"
	"errors"
	"time"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func (s *IdentityService) completeMember(m domain.IdentityMember) domain.IdentityMember {
	m.Permissions = s.complete(domain.IdentityPrincipal{Role: m.Role, IsOwner: m.IsOwner, Claims: m.Claims}).Permissions
	return m
}
func (s *IdentityService) completeMembership(m domain.IdentityMembership) domain.IdentityMembership {
	m.Permissions = s.complete(domain.IdentityPrincipal{Role: m.Role, IsOwner: m.IsOwner, Claims: m.Claims}).Permissions
	return m
}
func validatePage(limit, offset int) error {
	if limit < 1 || limit > 100 || offset < 0 {
		return domain.IdentityValidationError("pagination is invalid")
	}
	return nil
}
func (s *IdentityService) ListAccounts(ctx context.Context, p domain.IdentityPrincipal, limit, offset int) (domain.IdentityMembershipPage, error) {
	p, err := s.requireAuthority(ctx, p, "")
	if err != nil {
		return domain.IdentityMembershipPage{}, err
	}
	if err := validatePage(limit, offset); err != nil {
		return domain.IdentityMembershipPage{}, err
	}
	page, err := s.repository.ListAccounts(ctx, p, limit, offset)
	for i := range page.Items {
		page.Items[i] = s.completeMembership(page.Items[i])
	}
	return page, err
}
func (s *IdentityService) SwitchAccount(ctx context.Context, p domain.IdentityPrincipal, account string) (domain.IdentitySession, error) {
	p, err := s.requireAuthority(ctx, p, "")
	if err != nil {
		return domain.IdentitySession{}, err
	}
	token, record, err := s.newSession()
	if err != nil {
		return domain.IdentitySession{}, err
	}
	destination, err := s.repository.BackgroundAuthority(ctx, account, p.UserID)
	if err != nil {
		return domain.IdentitySession{}, err
	}
	if !destination.MembershipEnabled || destination.Principal.CredentialRevision != p.CredentialRevision || destination.Principal.MustChangePassword {
		return domain.IdentitySession{}, domain.ErrNotFound
	}
	record.ExpiresAt = p.SessionExpiresAt
	identity, expires, err := s.repository.SwitchAccount(ctx, p, destination, record)
	if err != nil {
		return domain.IdentitySession{}, err
	}
	return domain.IdentitySession{Token: token, ExpiresAt: expires, Identity: s.complete(identity)}, nil
}
func (s *IdentityService) CreateInvitation(ctx context.Context, p domain.IdentityPrincipal, email string, role domain.IdentityRole, claims []domain.IdentityPermission) (domain.IdentityIssuedInvitation, error) {
	p, err := s.requireAuthority(ctx, p, domain.UsersManage)
	if err != nil {
		return domain.IdentityIssuedInvitation{}, err
	}
	email, err = domain.NormalizeEmail(email)
	if err != nil {
		return domain.IdentityIssuedInvitation{}, err
	}
	if !domain.ValidRole(role) {
		return domain.IdentityIssuedInvitation{}, domain.IdentityValidationError("role is invalid")
	}
	if err := domain.ValidateClaims(claims); err != nil {
		return domain.IdentityIssuedInvitation{}, err
	}
	if !s.canDelegate(p, role, claims) {
		return domain.IdentityIssuedInvitation{}, domain.ErrForbidden
	}
	code, record, err := s.newSession()
	if err != nil {
		return domain.IdentityIssuedInvitation{}, err
	}
	input := domain.IdentityInvitation{ID: s.newID(), Email: email, Role: role, Claims: claims, Digest: record.Digest, CreatedAt: record.CreatedAt, ExpiresAt: record.CreatedAt.Add(7 * 24 * time.Hour)}
	invitation, err := s.repository.CreateInvitation(ctx, p, input)
	if err != nil {
		return domain.IdentityIssuedInvitation{}, err
	}
	return domain.IdentityIssuedInvitation{Invitation: invitation, Code: code}, nil
}
func (s *IdentityService) ListInvitations(ctx context.Context, p domain.IdentityPrincipal, limit, offset int) (domain.IdentityInvitationPage, error) {
	p, err := s.requireAuthority(ctx, p, domain.UsersManage)
	if err != nil {
		return domain.IdentityInvitationPage{}, err
	}
	if err := validatePage(limit, offset); err != nil {
		return domain.IdentityInvitationPage{}, err
	}
	return s.repository.ListInvitations(ctx, p, limit, offset)
}
func (s *IdentityService) RevokeInvitation(ctx context.Context, p domain.IdentityPrincipal, id string) error {
	p, err := s.requireAuthority(ctx, p, domain.UsersManage)
	if err != nil {
		return err
	}
	invitation, err := s.repository.Invitation(ctx, p.AccountID, id)
	if err != nil {
		return err
	}
	if invitation.AcceptedAt != nil {
		return domain.ErrNotFound
	}
	return s.repository.RevokeInvitation(ctx, p, invitation, s.now())
}
func (s *IdentityService) AcceptInvitation(ctx context.Context, p domain.IdentityPrincipal, code string) (domain.IdentityMembership, error) {
	p, err := s.requireAuthority(ctx, p, "")
	if err != nil {
		return domain.IdentityMembership{}, err
	}
	digest, err := TokenDigest(code)
	if err != nil {
		return domain.IdentityMembership{}, domain.ErrNotFound
	}
	for attempt := 0; attempt < 3; attempt++ {
		facts, err := s.repository.InvitationFacts(ctx, digest, p.UserID)
		if err != nil {
			return domain.IdentityMembership{}, err
		}
		v, issuer := facts.Invitation, s.complete(facts.Issuer.Principal)
		if v.Email != p.Email || v.AcceptedAt != nil || v.RevokedAt != nil || !v.ExpiresAt.After(s.now()) || facts.AlreadyMember ||
			!facts.Issuer.MembershipEnabled || issuer.MustChangePassword || !issuer.HasPermission(domain.UsersManage) || !s.canDelegate(issuer, v.Role, v.Claims) {
			return domain.IdentityMembership{}, domain.ErrNotFound
		}
		membership, err := s.repository.AcceptInvitation(ctx, p, facts)
		if !errors.Is(err, domain.ErrStaleFacts) {
			return s.completeMembership(membership), err
		}
		p, err = s.requireAuthority(ctx, p, "")
		if err != nil {
			return domain.IdentityMembership{}, err
		}
	}
	return domain.IdentityMembership{}, domain.ErrConflict
}
func (s *IdentityService) ListSystemUsers(ctx context.Context, p domain.IdentityPrincipal, limit, offset int) (domain.SystemUserPage, error) {
	p, err := s.requireAuthority(ctx, p, domain.SystemUsersManage)
	if err != nil {
		return domain.SystemUserPage{}, err
	}
	if err := validatePage(limit, offset); err != nil {
		return domain.SystemUserPage{}, err
	}
	return s.repository.ListSystemUsers(ctx, p, limit, offset)
}
func (s *IdentityService) UpdateSystemUser(ctx context.Context, p domain.IdentityPrincipal, id string, role domain.IdentityRole) (domain.SystemUser, error) {
	p, err := s.requireAuthority(ctx, p, domain.SystemUsersManage)
	if err != nil {
		return domain.SystemUser{}, err
	}
	if role != domain.Admin && role != domain.User {
		return domain.SystemUser{}, domain.IdentityValidationError("system role is invalid")
	}
	for attempt := 0; attempt < 3; attempt++ {
		facts, err := s.repository.SystemUserFacts(ctx, id)
		if err != nil {
			return domain.SystemUser{}, err
		}
		if facts.Target.Role == domain.Admin && role != domain.Admin && len(facts.Installation.AdministratorIDs) <= 1 {
			return domain.SystemUser{}, domain.ErrConflict
		}
		result, err := s.repository.UpdateSystemUser(ctx, p, facts, role)
		if !errors.Is(err, domain.ErrStaleFacts) {
			return result, err
		}
		p, err = s.requireAuthority(ctx, p, domain.SystemUsersManage)
		if err != nil {
			return domain.SystemUser{}, err
		}
	}
	return domain.SystemUser{}, domain.ErrConflict
}

func (s *IdentityService) BootstrapAdministrator(ctx context.Context, id string) error {
	for attempt := 0; attempt < 3; attempt++ {
		facts, err := s.repository.SystemUserFacts(ctx, id)
		if err != nil {
			return err
		}
		if len(facts.Installation.AdministratorIDs) != 0 {
			return domain.ErrConflict
		}
		err = s.repository.BootstrapAdministrator(ctx, facts)
		if !errors.Is(err, domain.ErrStaleFacts) {
			return err
		}
	}
	return domain.ErrConflict
}
