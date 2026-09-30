package interfaces

import (
	"context"

	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type IdentityPasswords interface {
	Hash(context.Context, string) (string, error)
	Verify(context.Context, string, string) (bool, error)
	Dummy(context.Context, string) error
}
type IdentityAuthorizer interface {
	Allows(identitymodels.IdentityPrincipal, identitymodels.IdentityPermission) bool
}
