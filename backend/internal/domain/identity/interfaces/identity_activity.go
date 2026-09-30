package interfaces

import (
	"context"

	"github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type IdentityActivityRepository interface {
	ActivityMemberships(context.Context, string) ([]models.IdentityActivityMembership, error)
	PersonalActivity(context.Context, models.IdentityPrincipal, models.IdentityActivityPageRequest) (models.PersonalActivity, error)
}

type IdentityActivityAuthority interface {
	ResolveAuthority(context.Context, models.IdentityPrincipal) (models.IdentityPrincipal, error)
}
