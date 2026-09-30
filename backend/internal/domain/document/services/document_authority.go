package services

import (
	"context"
	"errors"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func documentAuthorityError(err error) error {
	switch {
	case errors.Is(err, identity.ErrUnauthorized):
		return m.ErrUnauthorized
	case errors.Is(err, identity.ErrPasswordChange):
		return m.ErrPasswordChangeRequired
	case errors.Is(err, identity.ErrForbidden):
		return m.ErrForbidden
	default:
		return err
	}
}

func resolveDocumentAuthority(ctx context.Context, authority p.DocumentAuthority, actor m.DocumentActor, claims ...identity.IdentityPermission) (identity.IdentityPrincipal, error) {
	if authority == nil {
		return identity.IdentityPrincipal{}, m.ErrForbidden
	}
	var principal identity.IdentityPrincipal
	var err error
	if actor.ImportRunID != "" {
		if len(claims) == 0 {
			return principal, m.ErrForbidden
		}
		for _, claim := range claims {
			if claim != identity.DocumentsUpload {
				return principal, m.ErrForbidden
			}
		}
		principal, err = authority.ResolveBackgroundAuthority(ctx, actor.AccountID, actor.UserID, actor.CredentialRevision)
		claims = []identity.IdentityPermission{identity.PaperlessImport, identity.DocumentsRead, identity.DocumentsUpload}
	} else {
		principal, err = authority.ResolveAuthority(ctx, identity.IdentityPrincipal{AccountID: actor.AccountID, UserID: actor.UserID, SessionDigest: actor.SessionDigest, CredentialRevision: actor.CredentialRevision})
	}
	if err != nil {
		if actor.ImportRunID != "" {
			return principal, m.ErrForbidden
		}
		return principal, documentAuthorityError(err)
	}
	for _, claim := range claims {
		if !principal.HasPermission(claim) {
			return principal, m.ErrForbidden
		}
	}
	return principal, nil
}

func (s *DocumentIngestionService) authorize(ctx context.Context, actor m.DocumentActor, claims ...identity.IdentityPermission) error {
	_, err := resolveDocumentAuthority(ctx, s.authority, actor, claims...)
	return err
}

func (s *DocumentIngestionService) authorizeProcessing(ctx context.Context, actor m.DocumentActor, system bool) error {
	if system {
		return s.authorize(ctx, actor, identity.SystemDocumentProcessingManage)
	}
	principal, err := resolveDocumentAuthority(ctx, s.authority, actor)
	if err != nil {
		return err
	}
	if !principal.HasPermission(identity.DocumentsJobsRead) && !principal.HasPermission(identity.DocumentsReindex) {
		return m.ErrForbidden
	}
	return nil
}
