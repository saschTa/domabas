package services

import (
	"context"
	"errors"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func (s *PaperlessJobsService) authorize(ctx context.Context, actor d.DocumentActor, system bool) error {
	principal, err := s.authority.ResolveAuthority(ctx, i.IdentityPrincipal{AccountID: actor.AccountID, UserID: actor.UserID, SessionDigest: actor.SessionDigest, CredentialRevision: actor.CredentialRevision})
	return paperlessAuthorityError(principal, err, system)
}

func (s *PaperlessJobsService) authorizeRun(ctx context.Context, id string) error {
	actor, err := s.repository.WorkIdentity(ctx, id)
	if err != nil {
		return err
	}
	principal, err := s.authority.ResolveBackgroundAuthority(ctx, actor.AccountID, actor.UserID, actor.CredentialRevision)
	if errors.Is(err, i.ErrUnauthorized) {
		return d.ErrForbidden
	}
	return paperlessAuthorityError(principal, err, false)
}

func paperlessAuthorityError(principal i.IdentityPrincipal, err error, system bool) error {
	if errors.Is(err, i.ErrMembershipDisabled) {
		return d.ErrForbidden
	}
	if errors.Is(err, i.ErrUnauthorized) {
		return d.ErrUnauthorized
	}
	if errors.Is(err, i.ErrPasswordChange) || errors.Is(err, i.ErrForbidden) {
		return d.ErrForbidden
	}
	if err != nil {
		return err
	}
	claims := []i.IdentityPermission{i.PaperlessImport, i.DocumentsRead, i.DocumentsUpload}
	if system {
		claims = []i.IdentityPermission{i.SystemPaperlessManage}
	}
	for _, claim := range claims {
		if !principal.HasPermission(claim) {
			return d.ErrForbidden
		}
	}
	return nil
}
