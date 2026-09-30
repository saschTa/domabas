//go:build e2e

package e2e_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/jackc/pgx/v5"
)

func TestOCRCorrectionsAuthorizationLimitsAndDeletionPersistAcrossRestart(t *testing.T) {
	databaseURL := testdb.New(t)
	environment := newServerEnvironment(t, databaseURL)
	binary := filepath.Join(t.TempDir(), "server")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v\n%s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	baseURL, stop := startServer(t, binary, databaseURL, environment)
	defer func() { stop() }()
	api := &ingestionAPI{t: t, baseURL: baseURL, client: &http.Client{Timeout: 70 * time.Second}, spec: spec}
	register := func(email string) map[string]any {
		return api.request("", "POST", "/api/v1/auth/register", fmt.Sprintf(`{"accountName":"OCR acceptance","email":%q,"password":"OCR acceptance password 2026!"}`, email), 201, "AuthSession")
	}
	owner := register("ocr-owner@example.test")
	token := owner["token"].(string)
	identity := owner["identity"].(map[string]any)
	account := identity["account"].(map[string]any)["id"].(string)
	user := identity["user"].(map[string]any)["id"].(string)
	foreign := register("ocr-foreign@example.test")["token"].(string)
	original := fixtures.PDF(t, fixtures.Page{Text: "Machine source aardvark text retained exactly"}, fixtures.Page{Text: "Second PDF page source"})
	doc := api.upload(token, "two-pages.pdf", original, `{"title":"OCR acceptance","tags":["acceptance"]}`, false, 202)
	id := doc["id"].(string)
	path := "/api/v1/documents/" + id
	api.waitProcessing(token, id, "ready")
	initial := api.request(token, "GET", path+"/ocr", "", 200, "DocumentOCR")
	if initial["status"] != "available" || initial["origin"] != "machine" || !strings.Contains(initial["text"].(string), "aardvark") || initial["semanticIndexing"] != "ready" {
		t.Fatalf("machine OCR response: %v", initial)
	}
	api.request("", "GET", path+"/ocr", "", 401, "Error")
	api.request("", "PUT", path+"/ocr", "{", 401, "Error")
	api.request("", "DELETE", path, "", 401, "Error")
	for _, method := range []string{"GET", "PUT"} {
		api.request(foreign, method, path+"/ocr", `{"revision":1,"text":"foreign"}`, 404, "Error")
	}
	api.request(foreign, "DELETE", path, "", 404, "Error")
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	execSQL := func(query string, args ...any) {
		t.Helper()
		if _, err := connection.Exec(t.Context(), query, args...); err != nil {
			t.Fatal(err)
		}
	}
	execSQL("UPDATE memberships SET is_owner=false,role='viewer',claims='{}' WHERE account_id=$1 AND user_id=$2", account, user)
	api.request(token, "GET", path+"/ocr", "", 200, "DocumentOCR")
	api.request(token, "PUT", path+"/ocr", "{", 403, "Error")
	api.request(token, "DELETE", path, "", 403, "Error")
	execSQL("UPDATE memberships SET claims=ARRAY['documents:ocr:update','documents:delete'] WHERE account_id=$1 AND user_id=$2", account, user)
	body := func(revision float64, text string) string {
		value, err := json.Marshal(map[string]any{"revision": revision, "text": text})
		if err != nil {
			t.Fatal(err)
		}
		return string(value)
	}
	manual := "  correctedneedle\r\n世界 🚀\t exact trailing space "
	corrected := api.request(token, "PUT", path+"/ocr", body(initial["revision"].(float64), manual), 200, "DocumentOCR")
	if corrected["text"] != manual || corrected["origin"] != "manual" || corrected["revision"] != initial["revision"].(float64)+1 {
		t.Fatalf("manual OCR changed: %v", corrected)
	}
	api.assertMatch(token, "correctedneedle", id)
	if stale := api.search(token, "fulltext", "aardvark"); stale["total"] != float64(0) {
		t.Fatalf("replaced machine text remained searchable: %v", stale)
	}
	api.request(token, "PUT", path+"/ocr", body(initial["revision"].(float64), "stale editor"), 409, "Error")
	api.download(token, id, original, "application/pdf")
	api.waitProcessing(token, id, "ready")
	stop()
	api.baseURL, stop = startServer(t, binary, databaseURL, environment)
	retained := api.request(token, "GET", path+"/ocr", "", 200, "DocumentOCR")
	if retained["text"] != manual || retained["revision"] != corrected["revision"] || retained["semanticIndexing"] != "ready" {
		t.Fatalf("correction did not survive restart: %v", retained)
	}
	var machine string
	if err := connection.QueryRow(t.Context(), "SELECT ocr_machine_text FROM documents WHERE id=$1", id).Scan(&machine); err != nil || machine != initial["text"] {
		t.Fatalf("manual save replaced machine source: %q %v", machine, err)
	}
	revision := corrected["revision"].(float64)
	for _, invalid := range []string{`{}`, `{"revision":0}`, `{"revision":null,"text":"x"}`, `{"revision":1,"text":null}`, `{"revision":1,"text":"x","text":"y"}`, `{"revision":1,"text":"x","extra":1}`, `{"revision":1,"text":"\uD800"}`, `{"revision":1,"text":"\uDC00"}`, `{"revision":1,"text":"\u0000"}`, `{"revision":1,"text":"x"} {}`, string(append([]byte(`{"revision":1,"text":"`), 0xff, '"', '}'))} {
		api.request(token, "PUT", path+"/ocr", invalid, 400, "Error")
	}
	api.request(token, "PUT", path+"/ocr", body(revision, strings.Repeat("x", document.MaxOCRBytes+1)), 413, "Error")
	api.request(token, "PUT", path+"/ocr", body(revision, strings.Repeat("\t", document.MaxOCRBytes+1)), 413, "Error")
	api.request(token, "PUT", path+"/ocr", `{"revision":1,"text":"`+strings.Repeat(`\u0009`, document.MaxOCRBytes)+`"}`+strings.Repeat(" ", 4096), 413, "Error")
	escaped := fmt.Sprintf(`{"revision":%.0f,"text":"%s"}`, revision, strings.Repeat(`\u0009`, document.MaxOCRBytes))
	cleared := api.request(token, "PUT", path+"/ocr", escaped, 200, "DocumentOCR")
	if cleared["text"] != strings.Repeat("\t", document.MaxOCRBytes) || cleared["semanticIndexing"] != "not_required" {
		t.Fatal("maximum escaped text was not retained exactly without vectors")
	}
	processing := api.request(token, "GET", path+"/processing", "", 200, "DocumentProcessing")
	if processing["state"] != "ready" || processing["stage"] != "complete" {
		t.Fatalf("zero-chunk final original scheduled unnecessary processing: %v", processing)
	}
	if found := api.search(token, "fulltext", "correctedneedle"); found["total"] != float64(0) {
		t.Fatal("cleared OCR stayed searchable")
	}
	api.request(token, "DELETE", path, "", 204, "")
	for _, suffix := range []string{"", "/ocr", "/content", "/processing"} {
		api.request(token, "GET", path+suffix, "", 404, "Error")
	}
	api.request(token, "PUT", path+"/ocr", body(cleared["revision"].(float64), "revived"), 404, "Error")
	api.request(token, "DELETE", path, "", 404, "Error")
	var records, cleanup int
	if err := connection.QueryRow(t.Context(), `SELECT (SELECT count(*) FROM documents WHERE id=$1)+(SELECT count(*) FROM document_files WHERE document_id=$1)+(SELECT count(*) FROM document_processing WHERE document_id=$1)+(SELECT count(*) FROM document_chunks WHERE document_id=$1)+(SELECT count(*) FROM document_outbox WHERE document_id=$1)+(SELECT count(*) FROM document_uploads WHERE id=$1),(SELECT count(*) FROM document_cleanup WHERE document_id=$1)`, id).Scan(&records, &cleanup); err != nil || records != 0 || cleanup != 1 {
		t.Fatalf("logical delete retained content rows or lost cleanup identity: %d/%d %v", records, cleanup, err)
	}
	stop()
	api.baseURL, stop = startServer(t, binary, databaseURL, environment)
	api.request(token, "GET", path+"/ocr", "", 404, "Error")
	api.request(token, "GET", path+"/content", "", 404, "Error")
}
