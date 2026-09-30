//go:build integration

package repos_test

import (
	"context"
	"slices"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type documentDeniedAuthority struct {
	authority p.DocumentAuthority
	claim     string
}

func (a documentDeniedAuthority) ResolveAuthority(ctx context.Context, actor identity.IdentityPrincipal) (identity.IdentityPrincipal, error) {
	principal, err := a.authority.ResolveAuthority(ctx, actor)
	principal.Permissions = slices.DeleteFunc(principal.Permissions, func(claim identity.IdentityPermission) bool { return string(claim) == a.claim })
	return principal, err
}
func (a documentDeniedAuthority) ResolveBackgroundAuthority(ctx context.Context, account, user string, revision int64) (identity.IdentityPrincipal, error) {
	principal, err := a.authority.ResolveBackgroundAuthority(ctx, account, user, revision)
	principal.Permissions = slices.DeleteFunc(principal.Permissions, func(claim identity.IdentityPermission) bool { return string(claim) == a.claim })
	return principal, err
}
