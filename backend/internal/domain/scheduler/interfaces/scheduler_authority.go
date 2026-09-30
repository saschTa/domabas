package interfaces

import (
	"context"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type SchedulerAuthority interface {
	ResolveAuthority(context.Context, i.IdentityPrincipal) (i.IdentityPrincipal, error)
}
