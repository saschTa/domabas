package services

import (
	"context"

	"github.com/domabas/domabas/backend/internal/domain/identity/interfaces"
	"github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type IdentityActivityService struct {
	repository interfaces.IdentityActivityRepository
	authority  interfaces.IdentityActivityAuthority
	authorizer interfaces.IdentityAuthorizer
}

func NewIdentityActivityService(repository interfaces.IdentityActivityRepository, authority interfaces.IdentityActivityAuthority, authorizer interfaces.IdentityAuthorizer) *IdentityActivityService {
	return &IdentityActivityService{repository: repository, authority: authority, authorizer: authorizer}
}

func (s *IdentityActivityService) PersonalActivity(ctx context.Context, principal models.IdentityPrincipal, page models.IdentityActivityPageRequest) (models.PersonalActivity, error) {
	principal, err := s.authority.ResolveAuthority(ctx, principal)
	if err != nil {
		return models.PersonalActivity{}, err
	}
	memberships, err := s.repository.ActivityMemberships(ctx, principal.UserID)
	if err != nil {
		return models.PersonalActivity{}, err
	}
	page.Scope = models.IdentityActivityScope{}
	for _, member := range memberships {
		if !member.Enabled {
			continue
		}
		p := models.IdentityPrincipal{AccountID: member.AccountID, Role: member.Role, IsOwner: member.Owner, Claims: member.Claims}
		if !s.authorizer.Allows(p, models.ActivityReadOwn) {
			continue
		}
		page.Scope.Documents = append(page.Scope.Documents, member.AccountID)
		if s.authorizer.Allows(p, models.EmailManage) {
			page.Scope.Email = append(page.Scope.Email, member.AccountID)
		}
		if s.authorizer.Allows(p, models.DocumentsJobsRead) || s.authorizer.Allows(p, models.DocumentsReindex) {
			page.Scope.Batches = append(page.Scope.Batches, member.AccountID)
		}
		if s.authorizer.Allows(p, models.DocumentsRead) {
			page.Scope.Titles = append(page.Scope.Titles, member.AccountID)
		}
	}
	return s.repository.PersonalActivity(ctx, principal, page)
}
