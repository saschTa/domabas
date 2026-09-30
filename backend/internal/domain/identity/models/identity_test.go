package models

import (
	"strings"
	"testing"
)

func TestCanonicalEmailAndCredentialPolicies(t *testing.T) {
	for _, input := range []string{" Alice@Example.TEST ", "alice@example.test"} {
		email, err := NormalizeEmail(input)
		if err != nil || email != "alice@example.test" {
			t.Fatalf("%q -> %q %v", input, email, err)
		}
	}
	for _, input := range []string{"Name <alice@example.test>", "alice@example.test,bob@example.test", "ü@example.test", "a b@example.test", strings.Repeat("a", 245) + "@example.test"} {
		if _, err := NormalizeEmail(input); err == nil {
			t.Errorf("accepted invalid email %q", input)
		}
	}
	for _, password := range []string{"short", "abcdefg", "password", "12345678", "passwordpassword", strings.Repeat("a", 129), "invalid\xffpasswordlong"} {
		if ValidatePassword(password, "") == nil {
			t.Errorf("accepted new password %q", password)
		}
	}
	if err := ValidateCredential("x"); err != nil {
		t.Fatalf("short existing password must reach verification: %v", err)
	}
	for _, password := range []string{"eight!89", strings.Repeat("界", 8), strings.Repeat("🔐", 128)} {
		if err := ValidatePassword(password, ""); err != nil {
			t.Fatalf("valid password boundary: %v", err)
		}
	}
	if ValidatePassword("a-long-account@example.test", "a-long-account@example.test") == nil {
		t.Fatal("email accepted as password")
	}
}
