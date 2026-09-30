package models

import "testing"

func TestClaimCatalogReturnsIndependentCollections(t *testing.T) {
	first := ClaimCatalog()
	originalID, originalRole := first[0].ID, first[0].Roles[0]
	first[0].ID = "changed"
	first[0].Roles[0] = "changed"
	second := ClaimCatalog()
	if second[0].ID != originalID || second[0].Roles[0] != originalRole {
		t.Fatal("catalog exposed mutable policy")
	}
	for _, claims := range [][]IdentityPermission{{"*"}, {"unknown"}, {SystemUsersManage}, {DocumentsRead, DocumentsRead}, make([]IdentityPermission, 33)} {
		if ValidateClaims(claims) == nil {
			t.Fatalf("accepted invalid grants %v", claims)
		}
	}
	for _, claims := range [][]IdentityPermission{nil, {}, {DocumentsRead, UsersManage}} {
		if err := ValidateClaims(claims); err != nil {
			t.Fatal(err)
		}
	}
}
