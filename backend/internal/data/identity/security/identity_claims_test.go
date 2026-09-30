package security

import (
	"testing"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func TestScopedOwnershipAndDelegationUseOnePolicy(t *testing.T) {
	catalog := domain.ClaimCatalog()
	catalog = append(catalog, domain.IdentityClaim{ID: "documents:test-feature", Label: "Test feature", Scope: "namespace"})
	policy, err := newCasbinIdentityAuthorizer(catalog)
	if err != nil {
		t.Fatal(err)
	}
	catalog[len(catalog)-1].ID = "mutated"
	catalog[0].Roles[0] = "mutated"
	owner := domain.IdentityPrincipal{Role: domain.Admin, IsOwner: true, SystemRole: domain.User}
	if !policy.Allows(owner, "documents:test-feature") {
		t.Fatal("owner did not receive new registered namespace feature")
	}
	for _, claim := range []domain.IdentityPermission{"unknown", "*", domain.SystemUsersManage} {
		if policy.Allows(owner, claim) {
			t.Fatalf("owner bypassed scope for %s", claim)
		}
	}
	viewer := domain.IdentityPrincipal{Role: domain.Viewer, Claims: []domain.IdentityPermission{domain.UsersManage, domain.SystemUsersManage, "unknown"}, SystemRole: domain.User}
	if !policy.Allows(viewer, domain.UsersManage) || policy.Allows(viewer, domain.SystemUsersManage) || policy.Allows(viewer, domain.DocumentsCreate) {
		t.Fatal("explicit grants crossed scope or role authority")
	}
	if policy.CanDelegate("viewer", false, []string{"users:manage"}, "user", nil) {
		t.Fatal("role bundle escaped delegation ceiling")
	}
	if policy.CanDelegate("viewer", false, []string{"users:manage"}, "viewer", []string{"documents:create"}) {
		t.Fatal("explicit grant escaped delegation ceiling")
	}
	if !policy.CanDelegate("viewer", false, []string{"users:manage"}, "viewer", []string{"users:manage"}) {
		t.Fatal("valid limited delegation denied")
	}
	viewer.SystemRole = domain.Admin
	if !policy.Allows(viewer, domain.SystemUsersManage) || policy.Allows(viewer, domain.DocumentsCreate) {
		t.Fatal("system role changed namespace role")
	}
	viewer.MustChangePassword = true
	if policy.Allows(viewer, domain.SystemUsersManage) {
		t.Fatal("restricted session granted system authority")
	}
}

func TestThumbnailClaimBelongsToNormalNamespaceRolesAndOwners(t *testing.T) {
	policy, err := NewCasbinIdentityAuthorizer()
	if err != nil {
		t.Fatal(err)
	}
	for _, role := range []domain.IdentityRole{domain.Admin, domain.User, domain.Viewer} {
		actor := domain.IdentityPrincipal{Role: role}
		if !policy.Allows(actor, domain.DocumentsThumbnailsRead) {
			t.Fatalf("role %s lacks thumbnail claim", role)
		}
	}
	owner := domain.IdentityPrincipal{Role: domain.Viewer, IsOwner: true}
	if !policy.Allows(owner, domain.DocumentsThumbnailsRead) || policy.Allows(owner, "documents:thumbnails:unknown") || policy.Allows(owner, domain.SystemUsersManage) {
		t.Fatal("thumbnail owner grant escaped registered namespace scope")
	}
	for _, claim := range domain.ClaimCatalog() {
		if claim.ID == domain.DocumentsThumbnailsRead {
			if claim.Scope != "namespace" {
				t.Fatalf("thumbnail scope=%s", claim.Scope)
			}
			return
		}
	}
	t.Fatal("thumbnail claim missing from catalog")
}
