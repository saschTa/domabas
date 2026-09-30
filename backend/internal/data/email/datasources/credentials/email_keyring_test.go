package credentials

import (
	"encoding/base64"
	"strings"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

func TestCredentialEnvelopeRoundTripAndOwnership(t *testing.T) {
	encoded := base64.StdEncoding.EncodeToString(make([]byte, 32))
	keyring, err := NewEmailCredentialKeyring(`{"first":"`+encoded+`"}`, "first")
	if err != nil {
		t.Fatal(err)
	}
	identity := m.EmailCredentialIdentity{ProviderID: "provider", OwnerID: "owner", AccountID: "account"}
	for _, value := range []string{strings.Repeat("&", 4096), strings.Repeat("\"", 4096), strings.Repeat("\n", 4096), strings.Repeat("é", 2048)} {
		credentials := m.EmailCredentials{Username: strings.Repeat("u", 320), Password: value}
		id, ciphertext, err := keyring.Seal(identity, credentials)
		if err != nil {
			t.Fatal(err)
		}
		actual, err := keyring.Open(identity, id, ciphertext)
		if err != nil || actual != credentials {
			t.Fatalf("round trip failed: %v", err)
		}
		other := identity
		other.AccountID = "another"
		if _, err = keyring.Open(other, id, ciphertext); err == nil {
			t.Fatal("cross-namespace decrypt succeeded")
		}
		ciphertext[len(ciphertext)-1] ^= 1
		if _, err = keyring.Open(identity, id, ciphertext); err == nil {
			t.Fatal("corrupt ciphertext decrypted")
		}
	}
	if _, _, err := keyring.Seal(identity, m.EmailCredentials{Username: "u", Password: string([]byte{255})}); err == nil {
		t.Fatal("invalid UTF-8 accepted")
	}
}
func TestKeyringRejectsDuplicateAndPartialConfiguration(t *testing.T) {
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	for _, raw := range []string{"", `{"a":"` + key + `","a":"` + key + `"}`, `{"a":"bad"}`, `{"b":"` + key + `"}`, `{} trailing`} {
		if _, err := NewEmailCredentialKeyring(raw, "a"); err == nil {
			t.Fatal("invalid configuration accepted")
		}
	}
	if ring, err := NewEmailCredentialKeyring("", ""); err != nil || ring.Available() {
		t.Fatal("absent keys should disable email only")
	}
}
