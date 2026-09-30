//go:build integration

package repos

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/email/datasources"
	"github.com/domabas/domabas/backend/internal/data/email/datasources/credentials"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

func TestAutomaticCredentialsPreserveProvidersAcrossStartupAndRecovery(t *testing.T) {
	pool, source, _, actor := independentEmailFixture(t)
	database, err := postgres.NewPostgresDataSource(t.Context(), pool.Config().ConnString())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(database.Close)
	path := filepath.Join(t.TempDir(), "secrets", "email.key")
	load := func() (*credentials.EmailCredentialKeyring, error) {
		return datasources.CredentialKeyring(t.Context(), database.Database(), "", "", path)
	}
	rings := make(chan *credentials.EmailCredentialKeyring, 8)
	var group sync.WaitGroup
	for range 8 {
		group.Go(func() {
			ring, err := load()
			if err != nil {
				t.Error(err)
				return
			}
			rings <- ring
		})
	}
	group.Wait()
	close(rings)
	ring, err := load()
	if err != nil {
		t.Fatal(err)
	}
	provider := independentProvider(t, NewEmailRepository(source, ring), actor)
	for ring := range rings {
		got, err := NewEmailRepository(source, ring).Get(t.Context(), actor, provider.ID)
		if err != nil || got.CredentialState != "ready" || got.Username != "private-login" {
			t.Fatal("concurrent startup lost provider credentials", err)
		}
	}
	if _, err := load(); err != nil {
		t.Fatal("retained provider failed startup", err)
	}
	var original []byte
	if err := pool.QueryRow(t.Context(), "SELECT credential_ciphertext FROM email_providers WHERE id=$1", provider.ID).Scan(&original); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(path, path+".backup"); err != nil {
		t.Fatal(err)
	}
	if _, err := load(); err == nil {
		t.Fatal("missing retained key was replaced")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("startup wrote a replacement key", err)
	}
	if _, err := credentials.LoadFile(path, true); err != nil {
		t.Fatal(err)
	}
	if _, err := load(); err == nil {
		t.Fatal("wrong automatic key accepted")
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(path+".backup", path); err != nil {
		t.Fatal(err)
	}
	if _, err := load(); err != nil {
		t.Fatal("restored key rejected", err)
	}
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(map[string]string{"automatic": strings.TrimSpace(string(body))})
	if err != nil {
		t.Fatal(err)
	}
	for _, input := range [][2]string{{string(raw), ""}, {"", "automatic"}, {"invalid-private-keyring", "automatic"}} {
		if _, err := datasources.CredentialKeyring(t.Context(), database.Database(), input[0], input[1], path); err == nil {
			t.Fatal("partial or invalid override fell back to automatic key")
		}
	}
	explicit, err := datasources.CredentialKeyring(t.Context(), database.Database(), string(raw), "automatic", "unused-invalid-path")
	if err != nil {
		t.Fatal("explicit keyring did not bypass file", err)
	}
	identity := m.EmailCredentialIdentity{ProviderID: provider.ID, AccountID: actor.AccountID, OwnerID: actor.UserID}
	if got, err := explicit.Open(identity, "automatic", original); err != nil || got.Password != "fixture-password" {
		t.Fatal("automatic key could not transition to explicit keyring", err)
	}
	var retained []byte
	if err := pool.QueryRow(t.Context(), "SELECT credential_ciphertext FROM email_providers WHERE id=$1", provider.ID).Scan(&retained); err != nil || !bytes.Equal(original, retained) {
		t.Fatal("startup modified saved credentials", err)
	}
}
