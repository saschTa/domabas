package interfaces

import (
	"context"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type InvoiceAuthority interface {
	ResolveAuthority(context.Context, i.IdentityPrincipal) (i.IdentityPrincipal, error)
}
