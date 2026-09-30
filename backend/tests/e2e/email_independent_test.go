//go:build e2e

package e2e_test

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestIndependentEmailKeyRemovalAndRestorationPreserveCredentialEnvelope(t *testing.T) {
	databaseURL := testdb.New(t)
	environment := newServerEnvironment(t, databaseURL)
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	configured := append(append([]string{}, environment...),
		"EMAIL_CREDENTIAL_KEYS="+emailJSON(t, map[string]string{"independent": base64.StdEncoding.EncodeToString(key)}),
		"EMAIL_CREDENTIAL_ACTIVE_KEY_ID=independent", "EMAIL_IMAP_ALLOWED_HOSTS=", "EMAIL_IMAP_CA_FILE=")
	missing := append(append([]string{}, environment...), "EMAIL_CREDENTIAL_KEYS=", "EMAIL_CREDENTIAL_ACTIVE_KEY_ID=", "EMAIL_IMAP_ALLOWED_HOSTS=", "EMAIL_IMAP_CA_FILE=")
	binary := filepath.Join(t.TempDir(), "server")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build server: %v\n%s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	base, stopConfigured := startServer(t, binary, databaseURL, configured)
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 20 * time.Second}, spec: spec}
	session := api.request("", "POST", "/api/v1/auth/register", emailJSON(t, map[string]any{"accountName": "Independent key recovery", "email": "independent-key@example.test", "password": "Independent fixture password 2026!"}), 201, "AuthSession")
	token := session["token"].(string)
	id := uuid.NewString()
	input := map[string]any{"id": id, "label": "Retained private provider", "endpoint": "imap.example.test", "port": 993, "mailbox": "INBOX", "username": "recoverable-private-username", "password": "recoverable-private-password", "intervalMinutes": 15, "maxAgeDays": 30, "pageSize": 50, "enabled": false}
	provider := api.request(token, "POST", "/api/v1/email-providers", emailJSON(t, input), 201, "EmailProvider")
	if provider["credentialState"] != "ready" {
		t.Fatalf("configured provider unavailable: %v", provider["credentialState"])
	}
	db, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close(context.Background())
	var original []byte
	if err = db.QueryRow(t.Context(), `SELECT credential_ciphertext FROM email_providers WHERE id=$1`, id).Scan(&original); err != nil {
		t.Fatal(err)
	}
	stopConfigured()
	assertEmailStartupFailure(t, binary, databaseURL, missing, "email credential key file is missing")
	var unavailable []byte
	if err = db.QueryRow(t.Context(), `SELECT credential_ciphertext FROM email_providers WHERE id=$1`, id).Scan(&unavailable); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(original, unavailable) {
		t.Fatal("missing-key handling changed the retained credential envelope")
	}
	otherKey := make([]byte, 32)
	if _, err = rand.Read(otherKey); err != nil {
		t.Fatal(err)
	}
	otherKeyring := append(append([]string{}, environment...),
		"EMAIL_CREDENTIAL_KEYS="+emailJSON(t, map[string]string{"replacement": base64.StdEncoding.EncodeToString(otherKey)}),
		"EMAIL_CREDENTIAL_ACTIVE_KEY_ID=replacement", "EMAIL_IMAP_ALLOWED_HOSTS=", "EMAIL_IMAP_CA_FILE=")
	base, stopOtherKey := startServer(t, binary, databaseURL, otherKeyring)
	api.baseURL = base
	capabilities := api.request(token, "GET", "/api/v1/email-capabilities", "", 200, "EmailCapabilities")
	provider = api.request(token, "GET", "/api/v1/email-providers/"+id, "", 200, "EmailProvider")
	if capabilities["credentialsAvailable"] != true || provider["credentialState"] != "missing_key" || provider["username"] != nil || provider["hasPassword"] != true {
		t.Fatalf("missing historical key was confused with installation capability: available=%v state=%v usernamePresent=%v", capabilities["credentialsAvailable"], provider["credentialState"], provider["username"] != nil)
	}
	api.request(token, "POST", "/api/v1/email-connection-tests", emailJSON(t, map[string]any{"providerId": id, "expectedRevision": provider["revision"], "endpoint": "imap.example.test", "port": 993, "mailbox": "INBOX"}), 503, "Error")
	if err = db.QueryRow(t.Context(), `SELECT credential_ciphertext FROM email_providers WHERE id=$1`, id).Scan(&unavailable); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(original, unavailable) {
		t.Fatal("unavailable historical key triggered destructive rewrap")
	}
	stopOtherKey()
	base, stopRestored := startServer(t, binary, databaseURL, configured)
	defer stopRestored()
	api.baseURL = base
	provider = api.request(token, "GET", "/api/v1/email-providers/"+id, "", 200, "EmailProvider")
	if provider["credentialState"] != "ready" || provider["username"] != "recoverable-private-username" || provider["hasPassword"] != true || provider["consentState"] != "disabled" {
		t.Fatalf("restored key did not recover unchanged disabled provider: state=%v consent=%v usernameRestored=%v", provider["credentialState"], provider["consentState"], provider["username"] == "recoverable-private-username")
	}
	if _, exists := provider["password"]; exists {
		t.Fatal("restored key made password readable through API")
	}
}

func assertEmailStartupFailure(t *testing.T, binary, databaseURL string, environment []string, message string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, binary)
	command.Env = append(os.Environ(), environment...)
	command.Env = append(command.Env, "DATABASE_URL="+databaseURL, "HTTP_ADDR=127.0.0.1:0", "DOMABAS_ENV_FILE=")
	output, err := command.CombinedOutput()
	if err == nil || ctx.Err() != nil || !strings.Contains(string(output), message) {
		t.Fatalf("expected bounded email startup failure %q: %v\n%s", message, err, output)
	}
}
