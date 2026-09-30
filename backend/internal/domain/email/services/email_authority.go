package services

import (
	"context"
	"errors"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func (s *EmailService) authorize(ctx context.Context, actor m.EmailActor, importing bool) error {
	principal, err := s.authority.ResolveAuthority(ctx, i.IdentityPrincipal{AccountID: actor.AccountID, UserID: actor.UserID, SessionDigest: actor.SessionDigest, CredentialRevision: actor.CredentialRevision})
	return emailAuthorityError(principal, err, importing)
}

func emailAuthorityError(principal i.IdentityPrincipal, err error, importing bool) error {
	if errors.Is(err, i.ErrUnauthorized) || errors.Is(err, i.ErrForbidden) || errors.Is(err, i.ErrPasswordChange) {
		return m.ErrForbidden
	}
	if err != nil {
		return err
	}
	if !principal.HasPermission(i.EmailManage) || importing && (!principal.HasPermission(i.DocumentsUpload) || !principal.HasPermission(i.DocumentsRead)) {
		return m.ErrForbidden
	}
	return nil
}

func (s *EmailPollingService) authorizeRun(ctx context.Context, id string) error {
	provider, err := s.repository.Consent(ctx, id)
	if err != nil {
		return err
	}
	principal, err := s.authority.ResolveBackgroundAuthority(ctx, provider.AccountID, provider.OwnerID, provider.ConsentRevision)
	if err = emailAuthorityError(principal, err, true); err != nil {
		return err
	}
	if !provider.Enabled {
		return m.ErrStaleAttempt
	}
	return nil
}
