package security

import (
	"context"
	"errors"
	"strings"
	"testing"

	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func TestArgonRoundTripBoundsAndCancelledWaiters(t *testing.T) {
	passwords := NewArgon2IdentityPasswords()
	hash, err := passwords.Hash(t.Context(), "a reasonably long test password")
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		password string
		valid    bool
	}{{"a reasonably long test password", true}, {"x", false}} {
		valid, err := passwords.Verify(t.Context(), test.password, hash)
		if err != nil || valid != test.valid {
			t.Fatalf("verify=%v %v", valid, err)
		}
	}
	if _, err := passwords.Verify(t.Context(), "test", strings.Replace(hash, "m=65536", "m=999999999", 1)); err == nil {
		t.Fatal("unbounded parameters accepted")
	}
	passwords.permits <- struct{}{}
	passwords.permits <- struct{}{}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := passwords.Hash(ctx, "a reasonably long test password"); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled waiter: %v", err)
	}
	if len(passwords.permits) != 2 {
		t.Fatal("cancelled waiter released another derivation permit")
	}
	<-passwords.permits
	<-passwords.permits
	if err := passwords.Dummy(t.Context(), "x"); err != nil {
		t.Fatal(err)
	}
}
func TestFixedPolicyDeniesUnknownRolesAndPermissions(t *testing.T) {
	a, err := NewCasbinIdentityAuthorizer()
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		role       identitymodels.IdentityRole
		permission identitymodels.IdentityPermission
		allowed    bool
	}{{identitymodels.Admin, identitymodels.UsersManage, true}, {identitymodels.User, identitymodels.DocumentsCreate, true}, {identitymodels.Viewer, identitymodels.DocumentsRead, true}, {identitymodels.User, identitymodels.UsersManage, false}, {identitymodels.Viewer, identitymodels.DocumentsCreate, false}, {"administrator", identitymodels.UsersManage, false}, {identitymodels.Admin, "*", false}, {identitymodels.Admin, "", false}} {
		if got := a.Allows(identitymodels.IdentityPrincipal{Role: test.role}, test.permission); got != test.allowed {
			t.Errorf("%s/%s=%v", test.role, test.permission, got)
		}
	}
}
