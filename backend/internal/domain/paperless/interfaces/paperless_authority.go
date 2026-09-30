package interfaces

import (
	"context"

	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type PaperlessAuthority interface {
	ResolveAuthority(context.Context, identity.IdentityPrincipal) (identity.IdentityPrincipal, error)
	ResolveBackgroundAuthority(context.Context, string, string, int64) (identity.IdentityPrincipal, error)
}
