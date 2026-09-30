package interfaces

import (
	"context"

	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type EmailAuthority interface {
	ResolveAuthority(context.Context, i.IdentityPrincipal) (i.IdentityPrincipal, error)
	ResolveBackgroundAuthority(context.Context, string, string, int64) (i.IdentityPrincipal, error)
}
