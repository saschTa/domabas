//go:build e2e

package e2e_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"image/jpeg"
	"net/http"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/jackc/pgx/v5"
)

func TestThumbnailsBackfillSurvivesRestartAndProtectsContent(t *testing.T) {
	databaseURL := testdb.New(t)
	environment := newServerEnvironment(t, databaseURL)
	binary := filepath.Join(t.TempDir(), "server")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build server: %v: %s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	baseURL, stop := startServer(t, binary, databaseURL, environment)
	defer func() { stop() }()
	api := &ingestionAPI{t: t, baseURL: baseURL, client: &http.Client{Timeout: 125 * time.Second}, spec: spec}
	owner := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Thumbnails","email":"thumbnails@example.test","password":"Thumbnail fixture password 2026!"}`, 201, "AuthSession")
	token := owner["token"].(string)
	foreign := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Foreign thumbnails","email":"foreign-thumbnails@example.test","password":"Thumbnail fixture password 2026!"}`, 201, "AuthSession")["token"].(string)
	type thumbnailFixture struct {
		id, filename string
		original     []byte
		descriptor   map[string]any
		content      []byte
	}
	items := []thumbnailFixture{
		{filename: "thumbnail.png", original: fixtures.PNG(t, "Thumbnail backfill evidence")},
		{filename: "thumbnail.pdf", original: fixtures.PDF(t, fixtures.Page{Text: "Thumbnail first page"}, fixtures.Page{Text: "Second page remains in the original"})},
	}
	for index := range items {
		item := &items[index]
		uploaded := api.upload(token, item.filename, item.original, `{"title":"Thumbnail backfill"}`, true, 202)
		item.id = uploaded["id"].(string)
		api.waitProcessing(token, item.id, "ready")
	}
	stop()
	baseURL, stop = startServer(t, binary, databaseURL, environment)
	api.baseURL = baseURL
	for index := range items {
		item := &items[index]
		deadline := time.Now().Add(2 * time.Minute)
		for time.Now().Before(deadline) {
			document := api.request(token, "GET", "/api/v1/documents/"+item.id, "", 200, "Document")
			if descriptor, ok := document["thumbnail"].(map[string]any); ok {
				item.descriptor = descriptor
				break
			}
			time.Sleep(500 * time.Millisecond)
		}
		if item.descriptor == nil {
			t.Fatalf("automatic thumbnail did not arrive for %s", item.filename)
		}
		jobs := api.request(token, "GET", "/api/v1/document-jobs?pipeline=thumbnail&status=succeeded&documentId="+item.id, "", 200, "DocumentJobPage")
		history := jobs["items"].([]any)
		if len(history) != 1 {
			t.Fatalf("thumbnail generation missing from filtered job history: %v", jobs)
		}
		job := history[0].(map[string]any)
		if job["pipeline"] != "thumbnail" || job["stage"] != "complete" || job["rendererRevision"] != float64(1) || job["attempt"] != float64(1) || job["reason"] != "automatic" || job["isCurrent"] != true || job["startedAt"] == nil || job["finishedAt"] == nil {
			t.Fatalf("thumbnail history does not describe the completed attempt: %v", job)
		}
		for _, field := range []string{"configuration", "configurationRevision", "configurationFingerprint", "generation", "textSource"} {
			if _, exists := job[field]; exists {
				t.Fatalf("thumbnail job fabricated ingestion field %s", field)
			}
		}
		jobPath := "/api/v1/document-jobs/" + job["id"].(string)
		api.request(token, "GET", jobPath, "", 200, "DocumentJob")
		api.request(foreign, "GET", jobPath, "", 404, "Error")
		api.request("", "GET", jobPath, "", 401, "Error")
		originalHash := sha256.Sum256(item.original)
		if item.descriptor["sourceSha256"] != hex.EncodeToString(originalHash[:]) {
			t.Fatalf("thumbnail source identity differs from original: %v", item.descriptor)
		}
		path := "/api/v1/documents/" + item.id + "/thumbnail?sha256=" + item.descriptor["sha256"].(string)
		status, headers, content, readErr := api.send(token, "GET", path, "", nil)
		api.decode(status, headers, content, readErr, 200, "")
		if headers.Get("Content-Type") != "image/jpeg" || len(content) > 256<<10 || item.descriptor["size"] != float64(len(content)) {
			t.Fatalf("thumbnail MIME or size invalid: %s, %d, %v", headers.Get("Content-Type"), len(content), item.descriptor)
		}
		decoded, err := jpeg.Decode(bytes.NewReader(content))
		if err != nil || decoded.Bounds().Dx() > 256 || decoded.Bounds().Dy() > 360 {
			t.Fatalf("thumbnail dimensions invalid: %v", err)
		}
		if item.descriptor["width"] != float64(decoded.Bounds().Dx()) || item.descriptor["height"] != float64(decoded.Bounds().Dy()) {
			t.Fatal("thumbnail descriptor dimensions do not match JPEG")
		}
		outputHash := sha256.Sum256(content)
		if item.descriptor["sha256"] != hex.EncodeToString(outputHash[:]) {
			t.Fatal("thumbnail descriptor does not identify returned bytes")
		}
		item.content = content
		api.request("", "GET", path, "", 401, "Error")
		api.request(foreign, "GET", path, "", 404, "Error")
		api.request(token, "GET", "/api/v1/documents/"+item.id+"/thumbnail?sha256="+strings.Repeat("0", 64), "", 404, "Error")
		api.request(token, "GET", "/api/v1/documents/"+item.id+"/thumbnail", "", 400, "Error")
		status, headers, original, readErr := api.send(token, "GET", "/api/v1/documents/"+item.id+"/content", "", nil)
		api.decode(status, headers, original, readErr, 200, "")
		if !bytes.Equal(original, item.original) {
			t.Fatal("thumbnail generation changed the original")
		}
	}
	listed := api.request(token, "GET", "/api/v1/documents?limit=20", "", 200, "DocumentList")
	for _, value := range listed["items"].([]any) {
		if value.(map[string]any)["thumbnail"] == nil {
			t.Fatal("browse descriptor missing a ready thumbnail")
		}
	}
	searched := api.request(token, "POST", "/api/v1/documents/search", `{"query":"","mode":"fulltext","limit":20}`, 200, "DocumentSearchResults")
	for _, value := range searched["items"].([]any) {
		if value.(map[string]any)["document"].(map[string]any)["thumbnail"] == nil {
			t.Fatal("search descriptor missing a ready thumbnail")
		}
	}
	stop()
	baseURL, stop = startServer(t, binary, databaseURL, environment)
	api.baseURL = baseURL
	for _, item := range items {
		path := "/api/v1/documents/" + item.id + "/thumbnail?sha256=" + item.descriptor["sha256"].(string)
		status, headers, content, readErr := api.send(token, "GET", path, "", nil)
		api.decode(status, headers, content, readErr, 200, "")
		if !bytes.Equal(content, item.content) {
			t.Fatal("persisted thumbnail changed across backend restart")
		}
		api.request(token, "DELETE", "/api/v1/documents/"+item.id, "", 204, "")
		api.request(token, "GET", path, "", 404, "Error")
	}
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	var artifacts, succeeded int
	if err = connection.QueryRow(t.Context(), "SELECT (SELECT count(*) FROM document_thumbnails),(SELECT count(*) FROM document_thumbnail_jobs WHERE status='succeeded')").Scan(&artifacts, &succeeded); err != nil {
		t.Fatal(err)
	}
	if artifacts != 0 || succeeded != len(items) {
		t.Fatalf("deletion or idempotent restart failed: artifacts=%d successful jobs=%d", artifacts, succeeded)
	}
}
