package security

import (
	"fmt"
	"slices"

	"github.com/casbin/casbin/v3"
	"github.com/casbin/casbin/v3/model"
	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type CasbinIdentityAuthorizer struct {
	enforcer *casbin.SyncedEnforcer
	catalog  []identitymodels.IdentityClaim
}

func NewCasbinIdentityAuthorizer() (*CasbinIdentityAuthorizer, error) {
	return newCasbinIdentityAuthorizer(identitymodels.ClaimCatalog())
}
func newCasbinIdentityAuthorizer(claims []identitymodels.IdentityClaim) (*CasbinIdentityAuthorizer, error) {
	catalog := make([]identitymodels.IdentityClaim, len(claims))
	for i, claim := range claims {
		catalog[i] = claim
		catalog[i].Roles = append([]identitymodels.IdentityRole(nil), claim.Roles...)
	}
	m, err := model.NewModelFromString(`[request_definition]
r = role, permission
[policy_definition]
p = role, permission
[policy_effect]
e = some(where (p.eft == allow))
[matchers]
m = r.role == p.role && r.permission == p.permission`)
	if err != nil {
		return nil, fmt.Errorf("build authorization model: %w", err)
	}
	enforcer, err := casbin.NewSyncedEnforcer(m)
	if err != nil {
		return nil, fmt.Errorf("build authorizer: %w", err)
	}
	for _, claim := range catalog {
		for _, role := range claim.Roles {
			if _, err := enforcer.AddPolicy([]string{claim.Scope + ":" + string(role), string(claim.ID)}); err != nil {
				return nil, fmt.Errorf("load authorization policy: %w", err)
			}
		}
	}
	return &CasbinIdentityAuthorizer{enforcer: enforcer, catalog: catalog}, nil
}
func (a *CasbinIdentityAuthorizer) Allows(p identitymodels.IdentityPrincipal, permission identitymodels.IdentityPermission) bool {
	claims := make([]string, len(p.Claims))
	for i, claim := range p.Claims {
		claims[i] = string(claim)
	}
	return !p.MustChangePassword && a.AllowsAuthority(string(p.Role), p.IsOwner, claims, string(p.SystemRole), string(permission))
}
func (a *CasbinIdentityAuthorizer) AllowsAuthority(role string, owner bool, claims []string, systemRole, permission string) bool {
	scope := ""
	for _, claim := range a.catalog {
		if string(claim.ID) == permission {
			scope = claim.Scope
			break
		}
	}
	if scope == "" {
		return false
	}
	if scope == "namespace" {
		if !identitymodels.ValidRole(identitymodels.IdentityRole(role)) {
			return false
		}
		if owner || slices.Contains(claims, permission) {
			return true
		}
	} else {
		role = systemRole
	}
	allowed, err := a.enforcer.Enforce(scope+":"+role, permission)
	return err == nil && allowed
}
func (a *CasbinIdentityAuthorizer) CanDelegate(role string, owner bool, claims []string, targetRole string, targetClaims []string) bool {
	if !identitymodels.ValidRole(identitymodels.IdentityRole(targetRole)) {
		return false
	}
	for _, claim := range a.catalog {
		if claim.Scope == "namespace" && a.AllowsAuthority(targetRole, false, targetClaims, "", string(claim.ID)) && !a.AllowsAuthority(role, owner, claims, "", string(claim.ID)) {
			return false
		}
	}
	return true
}
