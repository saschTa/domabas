package services

import (
	"context"
	"errors"

	m "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func (s *IdentityService) sessionAuthority(ctx context.Context, digest string) (m.IdentityPrincipal, error) {
	if digest == "" {
		return m.IdentityPrincipal{}, m.ErrUnauthorized
	}
	facts, err := s.repository.SessionAuthority(ctx, digest)
	if errors.Is(err, m.ErrNotFound) {
		return m.IdentityPrincipal{}, m.ErrUnauthorized
	}
	if err != nil {
		return m.IdentityPrincipal{}, err
	}
	if err := facts.ValidateSession(digest); err != nil {
		return m.IdentityPrincipal{}, err
	}
	return s.complete(facts.Principal), nil
}

func (s *IdentityService) resolveAuthority(ctx context.Context, actor m.IdentityPrincipal, normal bool) (m.IdentityPrincipal, error) {
	if actor.UserID == "" || actor.AccountID == "" || actor.CredentialRevision <= 0 {
		return m.IdentityPrincipal{}, m.ErrUnauthorized
	}
	current, err := s.sessionAuthority(ctx, actor.SessionDigest)
	if err != nil {
		return m.IdentityPrincipal{}, err
	}
	if current.UserID != actor.UserID || current.AccountID != actor.AccountID || current.CredentialRevision != actor.CredentialRevision {
		return m.IdentityPrincipal{}, m.ErrUnauthorized
	}
	if normal && current.MustChangePassword {
		return m.IdentityPrincipal{}, m.ErrPasswordChange
	}
	return current, nil
}

func (s *IdentityService) ResolveAuthority(ctx context.Context, actor m.IdentityPrincipal) (m.IdentityPrincipal, error) {
	return s.resolveAuthority(ctx, actor, true)
}

func (s *IdentityService) ResolveBackgroundAuthority(ctx context.Context, accountID, userID string, credentialRevision int64) (m.IdentityPrincipal, error) {
	if accountID == "" || userID == "" || credentialRevision <= 0 {
		return m.IdentityPrincipal{}, m.ErrUnauthorized
	}
	facts, err := s.repository.BackgroundAuthority(ctx, accountID, userID)
	if errors.Is(err, m.ErrNotFound) {
		return m.IdentityPrincipal{}, m.ErrUnauthorized
	}
	if err != nil {
		return m.IdentityPrincipal{}, err
	}
	p := facts.Principal
	if !facts.MembershipEnabled || p.AccountID != accountID || p.UserID != userID || p.CredentialRevision != credentialRevision {
		return m.IdentityPrincipal{}, m.ErrUnauthorized
	}
	if p.MustChangePassword {
		return m.IdentityPrincipal{}, m.ErrPasswordChange
	}
	p.SessionDigest = ""
	p.SessionExpiresAt = nil
	return s.complete(p), nil
}

func (s *IdentityService) requireAuthority(ctx context.Context, actor m.IdentityPrincipal, permission m.IdentityPermission) (m.IdentityPrincipal, error) {
	current, err := s.ResolveAuthority(ctx, actor)
	if err != nil {
		return m.IdentityPrincipal{}, err
	}
	if permission != "" && !current.HasPermission(permission) {
		return m.IdentityPrincipal{}, m.ErrForbidden
	}
	return current, nil
}

func (s *IdentityService) canDelegate(actor m.IdentityPrincipal, role m.IdentityRole, claims []m.IdentityPermission) bool {
	proposed := s.complete(m.IdentityPrincipal{Role: role, Claims: claims})
	for _, permission := range proposed.Permissions {
		if !actor.HasPermission(permission) {
			return false
		}
	}
	return true
}
