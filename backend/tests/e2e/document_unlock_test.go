//go:build e2e

package e2e_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	pdf "github.com/domabas/domabas/backend/tests/fixtures/pdf"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/jackc/pgx/v5"
)

func TestPasswordPDFUnlockStoresReadableOriginalAndResumesIngestion(t *testing.T) {
	databaseURL := testdb.New(t)
	environment := newServerEnvironment(t, databaseURL)
	binary := filepath.Join(t.TempDir(), "server")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v %s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	baseURL, stop := startServer(t, binary, databaseURL, environment)
	defer func() { stop() }()
	api := &ingestionAPI{t: t, baseURL: baseURL, client: &http.Client{Timeout: 125 * time.Second}, spec: spec}
	owner := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"PDF unlock","email":"unlock@example.test","password":"Account fixture password 2026!"}`, 201, "AuthSession")
	token := owner["token"].(string)
	original := pdf.PasswordPDF(" test123 ", "Unlocked searchable platypus evidence")
	doc := api.upload(token, "protected.pdf", original, `{"title":"Password PDF","tags":["unlock"]}`, true, 202)
	id := doc["id"].(string)
	path := "/api/v1/documents/" + id
	processing := api.waitProcessing(token, id, "failed")
	if processing["failureCode"] != "encrypted_pdf" {
		t.Fatalf("locked PDF misclassified: %v", processing)
	}
	api.request("", "POST", path+"/unlock", `{"password":" test123 ","generation":1}`, 401, "Error")
	wrong := api.request(token, "POST", path+"/unlock", `{"password":"wrong","generation":1}`, 400, "Error")
	if wrong["code"] != "invalid_pdf_password" {
		t.Fatalf("wrong password response: %v", wrong)
	}
	status, headers, data, err := api.send(token, "GET", path+"/content", "", nil)
	api.decode(status, headers, data, err, 200, "")
	if !bytes.Equal(original, data) {
		t.Fatal("wrong password changed original")
	}
	for _, body := range []string{`{"password":null,"generation":1}`, `{"password":"x","password":"y","generation":1}`, `{"password":"","generation":1}`, `{"password":"x","generation":0}`} {
		api.request(token, "POST", path+"/unlock", body, 400, "Error")
	}
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	identity := owner["identity"].(map[string]any)
	user := identity["user"].(map[string]any)["id"].(string)
	if _, err = connection.Exec(t.Context(), "UPDATE memberships SET is_owner=false,role='viewer' WHERE user_id=$1", user); err != nil {
		t.Fatal(err)
	}
	api.request(token, "POST", path+"/unlock", `{"password":" test123 ","generation":1}`, 403, "Error")
	if _, err = connection.Exec(t.Context(), "UPDATE memberships SET is_owner=true WHERE user_id=$1", user); err != nil {
		t.Fatal(err)
	}
	queued := api.request(token, "POST", path+"/unlock", `{"password":" test123 ","generation":1}`, 202, "DocumentProcessing")
	if queued["generation"] != float64(2) {
		t.Fatal("new generation missing", queued)
	}
	api.request(token, "POST", path+"/unlock", `{"password":" test123 ","generation":1}`, 409, "Error")
	api.waitProcessing(token, id, "ready")
	text := api.request(token, "GET", path+"/ocr", "", 200, "DocumentOCR")
	if !strings.Contains(text["text"].(string), "platypus") {
		t.Fatal("unlocked text unavailable")
	}
	status, headers, data, err = api.send(token, "GET", path+"/content", "", nil)
	api.decode(status, headers, data, err, 200, "")
	if bytes.Equal(original, data) || !bytes.HasPrefix(data, []byte("%PDF-")) {
		t.Fatal("stored PDF was not replaced")
	}
	updated := api.request(token, "GET", path, "", 200, "Document")
	file := updated["file"].(map[string]any)
	digest := sha256.Sum256(data)
	if file["sha256"] != hex.EncodeToString(digest[:]) || file["size"] != float64(len(data)) || file["originalFilename"] != "protected.pdf" {
		t.Fatalf("incorrect unlocked file identity: %v", file)
	}
	stop()
	baseURL, stop = startServer(t, binary, databaseURL, environment)
	api.baseURL = baseURL
	status, headers, restarted, err := api.send(token, "GET", path+"/content", "", nil)
	api.decode(status, headers, restarted, err, 200, "")
	if !bytes.Equal(data, restarted) {
		t.Fatal("unlocked bytes did not survive restart")
	}
}
