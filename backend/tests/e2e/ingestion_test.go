//go:build e2e

package e2e_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/jackc/pgx/v5"
)

type ingestionAPI struct {
	t       *testing.T
	baseURL string
	client  *http.Client
	spec    *openapi3.T
}

func (api *ingestionAPI) send(token, method, path, contentType string, body io.Reader) (int, http.Header, []byte, error) {
	request, err := http.NewRequest(method, api.baseURL+path, body)
	if err != nil {
		return 0, nil, nil, err
	}
	request.Header.Set("Content-Type", contentType)
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	response, err := api.client.Do(request)
	if err != nil {
		return 0, nil, nil, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 21<<20))
	return response.StatusCode, response.Header, data, err
}

func (api *ingestionAPI) decode(status int, headers http.Header, data []byte, err error, expected int, schema string) map[string]any {
	api.t.Helper()
	if err != nil || status != expected {
		api.t.Fatalf("HTTP status %d, want %d: %v: %s", status, expected, err, data)
	}
	if !strings.Contains(headers.Get("Cache-Control"), "no-store") {
		api.t.Fatal("private document response permits caching")
	}
	if schema == "" {
		return nil
	}
	var result map[string]any
	if err := json.Unmarshal(data, &result); err != nil {
		api.t.Fatalf("decode %s: %v: %s", schema, err, data)
	}
	if err := api.spec.Components.Schemas[schema].Value.VisitJSON(result); err != nil {
		api.t.Fatalf("response violates %s: %v", schema, err)
	}
	return result
}

func (api *ingestionAPI) request(token, method, path, body string, expected int, schema string) map[string]any {
	api.t.Helper()
	status, headers, data, err := api.send(token, method, path, "application/json", strings.NewReader(body))
	return api.decode(status, headers, data, err, expected, schema)
}

func multipartDocument(filename string, data []byte, metadata string, fileFirst bool) ([]byte, string, error) {
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	file := func() error {
		header := textproto.MIMEHeader{}
		header.Set("Content-Disposition", fmt.Sprintf(`form-data; name="file"; filename="%s"`, filename))
		header.Set("Content-Type", "application/octet-stream")
		part, err := writer.CreatePart(header)
		if err != nil {
			return err
		}
		_, err = part.Write(data)
		return err
	}
	meta := func() error { return writer.WriteField("metadata", metadata) }
	parts := []func() error{meta, file}
	if fileFirst {
		parts = []func() error{file, meta}
	}
	for _, part := range parts {
		if err := part(); err != nil {
			return nil, "", err
		}
	}
	if err := writer.Close(); err != nil {
		return nil, "", err
	}
	return body.Bytes(), writer.FormDataContentType(), nil
}

func (api *ingestionAPI) upload(token, filename string, bytes []byte, metadata string, fileFirst bool, expected int) map[string]any {
	api.t.Helper()
	body, contentType, err := multipartDocument(filename, bytes, metadata, fileFirst)
	if err != nil {
		api.t.Fatal(err)
	}
	schema := "Document"
	if expected != http.StatusAccepted {
		schema = "Error"
	}
	status, headers, data, err := api.send(token, "POST", "/api/v1/documents/upload", contentType, strings.NewReader(string(body)))
	return api.decode(status, headers, data, err, expected, schema)
}

func (api *ingestionAPI) waitProcessing(token, id, expected string) map[string]any {
	api.t.Helper()
	deadline := time.Now().Add(4 * time.Minute)
	for time.Now().Before(deadline) {
		result := api.request(token, "GET", "/api/v1/documents/"+id+"/processing", "", 200, "DocumentProcessing")
		if result["state"] == "ready" || result["state"] == "failed" {
			if result["state"] != expected {
				api.t.Fatalf("document reached unexpected terminal state: %v", result)
			}
			return result
		}
		time.Sleep(200 * time.Millisecond)
	}
	api.t.Fatal("real document ingestion exceeded the test deadline")
	return nil
}

func (api *ingestionAPI) download(token, id string, expected []byte, mediaType string) {
	api.t.Helper()
	status, headers, data, err := api.send(token, "GET", "/api/v1/documents/"+id+"/content", "", nil)
	api.decode(status, headers, data, err, 200, "")
	if !bytes.Equal(data, expected) || headers.Get("Content-Type") != mediaType || !strings.HasPrefix(headers.Get("Content-Disposition"), "attachment;") || headers.Get("X-Content-Type-Options") != "nosniff" {
		api.t.Fatalf("download changed bytes or unsafe response headers: %v", headers)
	}
}

func (api *ingestionAPI) search(token, mode, query string) map[string]any {
	api.t.Helper()
	body, _ := json.Marshal(map[string]any{"mode": mode, "query": query})
	return api.request(token, "POST", "/api/v1/documents/search", string(body), 200, "DocumentSearchResults")
}

func (api *ingestionAPI) assertMatch(token, query, id string) {
	api.t.Helper()
	result := api.search(token, "fulltext", query)
	for _, item := range result["items"].([]any) {
		if item.(map[string]any)["document"].(map[string]any)["id"] == id {
			return
		}
	}
	api.t.Fatalf("extracted or manual text %q missing from search: %v", query, result)
}

func (api *ingestionAPI) assertRevokedUploadCannotCommit(databaseURL, token, uploaderID string) {
	api.t.Helper()
	ctx, cancel := context.WithTimeout(api.t.Context(), 20*time.Second)
	defer cancel()
	connection, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		api.t.Fatal(err)
	}
	defer connection.Close(context.Background())
	var beforeDocuments, beforeOutbox int
	if err := connection.QueryRow(ctx, `SELECT (SELECT count(*) FROM documents),(SELECT count(*) FROM document_outbox)`).Scan(&beforeDocuments, &beforeOutbox); err != nil {
		api.t.Fatal(err)
	}
	reader, writer := io.Pipe()
	defer reader.Close()
	defer writer.Close()
	multipartWriter := multipart.NewWriter(writer)
	finish := make(chan struct{})
	var releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { close(finish) }) }
	defer release()
	image := fixtures.PNG(api.t, "This upload is revoked while streaming.")
	written := make(chan struct{})
	go func() {
		defer close(written)
		defer writer.Close()
		if multipartWriter.WriteField("metadata", `{"title":"Revoked upload"}`) != nil {
			return
		}
		part, err := multipartWriter.CreateFormFile("file", "revoked.png")
		if err != nil {
			return
		}
		if _, err := part.Write(image[:512]); err != nil {
			return
		}
		<-finish
		_, _ = part.Write(image[512:])
		_ = multipartWriter.Close()
	}()
	result := make(chan struct {
		status int
		err    error
	}, 1)
	go func() {
		status, _, _, err := api.send(token, "POST", "/api/v1/documents/upload", multipartWriter.FormDataContentType(), reader)
		result <- struct {
			status int
			err    error
		}{status, err}
	}()
	for {
		var receiving int
		if err := connection.QueryRow(ctx, `SELECT count(*) FROM document_uploads WHERE uploader_id=$1 AND state='receiving'`, uploaderID).Scan(&receiving); err != nil {
			api.t.Fatal(err)
		}
		if receiving > 0 {
			break
		}
		select {
		case <-ctx.Done():
			api.t.Fatal("upload did not reach the durable reservation barrier")
		case <-time.After(10 * time.Millisecond):
		}
	}
	api.request(token, "DELETE", "/api/v1/auth/session", "", 204, "")
	release()
	select {
	case response := <-result:
		if response.err != nil || response.status != 401 {
			api.t.Fatalf("revoked upload was not rejected at acceptance: %d %v", response.status, response.err)
		}
	case <-ctx.Done():
		api.t.Fatal("revoked upload did not stop")
	}
	reader.Close()
	writer.Close()
	<-written
	var afterDocuments, afterOutbox int
	if err := connection.QueryRow(ctx, `SELECT (SELECT count(*) FROM documents),(SELECT count(*) FROM document_outbox)`).Scan(&afterDocuments, &afterOutbox); err != nil {
		api.t.Fatal(err)
	}
	if afterDocuments != beforeDocuments || afterOutbox != beforeOutbox {
		api.t.Fatal("revoked streamed upload committed a document or promised processing")
	}
}

func TestRealDocumentIngestionSearchAndOriginalsPersist(t *testing.T) {
	databaseURL := testdb.New(t)
	serverEnvironment := newServerEnvironment(t, databaseURL)
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
	baseURL, stop := startServer(t, binary, databaseURL, serverEnvironment)
	api := &ingestionAPI{t: t, baseURL: baseURL, client: &http.Client{Timeout: 70 * time.Second}, spec: spec}
	register := func(email string) map[string]any {
		return api.request("", "POST", "/api/v1/auth/register", fmt.Sprintf(`{"accountName":"Upload test","email":%q,"password":"Document test password 2026!"}`, email), 201, "AuthSession")
	}
	owner := register("upload-owner@example.test")
	token := owner["token"].(string)
	accountID := owner["identity"].(map[string]any)["account"].(map[string]any)["id"].(string)
	other := register("upload-other@example.test")
	otherToken := other["token"].(string)
	configuration := api.request(token, "GET", "/api/v1/system/document-processing", "", 200, "DocumentProcessingConfiguration")
	if configuration["ready"] != true || configuration["embeddingDimensions"] != float64(768) {
		t.Fatal("actual verified processing models are not ready")
	}
	api.request(otherToken, "PUT", "/api/v1/system/document-processing", "{", 403, "Error")
	configured := api.request(token, "PUT", "/api/v1/system/document-processing", `{"language":"eng","segmentation":"auto"}`, 200, "DocumentProcessingConfiguration")
	if configured["revision"].(float64) != configuration["revision"].(float64)+1 {
		t.Fatal("OCR configuration revision did not advance")
	}
	api.request(token, "PUT", "/api/v1/system/document-processing", `{"language":"eng","segmentation":"auto","model":"arbitrary"}`, 400, "Error")
	api.request(token, "PUT", "/api/v1/system/document-processing", `{"language":"eng","language":"deu","segmentation":"auto"}`, 400, "Error")

	png := fixtures.PNG(t, "Electricity invoice for household power", "Amount due is 240 euros.", "Payment requested before October.")
	metadata := `{"title":"Imported letter","kind":"letter","tags":[" Finance ","ENERGY"],"sender":"Example Utility","recipients":["Alex Reader"],"documentDate":"2026-09-15","subject":"Meter settlement","messageId":"record-101"}`
	doc := api.upload(token, "electricity.png", png, metadata, true, 202)
	id := doc["id"].(string)
	file := doc["file"].(map[string]any)
	hash := sha256.Sum256(png)
	if file["sha256"] != hex.EncodeToString(hash[:]) || file["size"] != float64(len(png)) || file["mediaType"] != "image/png" || doc["sender"] != "Example Utility" {
		t.Fatalf("incorrect persisted file identity or manual metadata: %v", doc)
	}
	api.download(token, id, png, "image/png")
	processing := api.waitProcessing(token, id, "ready")
	if processing["configurationRevision"] != configured["revision"] || processing["ocrLanguage"] != "eng" || processing["generation"] != float64(1) {
		t.Fatalf("job did not snapshot processing configuration: %v", processing)
	}
	api.assertMatch(token, "electricity", id)
	api.assertMatch(token, "Alex", id)
	for _, mode := range []string{"fulltext", "semantic", "hybrid"} {
		results := api.search(token, mode, "electricity")
		found := false
		for _, value := range results["items"].([]any) {
			summary := value.(map[string]any)["document"].(map[string]any)
			if summary["id"] == id {
				original, ok := summary["original"].(map[string]any)
				if !ok || len(original) != 3 || original["sha256"] != file["sha256"] || original["mediaType"] != file["mediaType"] || original["size"] != file["size"] {
					t.Fatalf("%s search original differs from accepted file: %v", mode, summary)
				}
				found = true
			}
		}
		if !found {
			t.Fatalf("%s search omitted accepted original", mode)
		}
	}
	api.request(token, "POST", "/api/v1/documents/"+id+"/retry", "", 409, "Error")
	duplicate := api.upload(token, "renamed.pdf", png, `{"title":"Duplicate"}`, false, 409)
	if duplicate["code"] != "duplicate_document" {
		t.Fatalf("duplicate was not rejected uniformly: %v", duplicate)
	}
	foreign := api.upload(otherToken, "same.png", png, `{"title":"Independent original"}`, false, 202)
	foreignID := foreign["id"].(string)
	api.download(otherToken, foreignID, png, "image/png")
	api.waitProcessing(otherToken, foreignID, "ready")
	for _, path := range []string{"", "/content", "/processing"} {
		api.request(otherToken, "GET", "/api/v1/documents/"+id+path, "", 404, "Error")
	}
	api.request(otherToken, "PATCH", "/api/v1/documents/"+id, `{"title":"Intrusion"}`, 404, "Error")
	api.request(otherToken, "POST", "/api/v1/documents/"+id+"/retry", "", 404, "Error")

	jpeg := fixtures.JPEG(t, "Garden planting instructions", "Water roses and prune flowering shrubs.", "Compost enriches soil for vegetables.")
	for _, fixture := range []struct {
		name, mediaType, query string
		data                   []byte
	}{
		{"garden.jpeg", "image/jpeg", "vegetables", jpeg},
		{"native.pdf", "application/pdf", "cardiology", fixtures.PDF(t, fixtures.Page{Text: "Hospital cardiology appointment for a medical examination"})},
		{"scan.pdf", "application/pdf", "landlord", fixtures.PDF(t, fixtures.Page{JPEG: fixtures.JPEG(t, "Residential property lease agreement", "The landlord provides accommodation.")})},
		{"oversized-page.pdf", "application/pdf", "pixelbudget", fixtures.PDF(t, fixtures.Page{Width: 5952, Height: 8418, Text: "Native adaptive page", JPEG: fixtures.JPEG(t, "Scanned pixelbudget evidence")})},
		{"mixed.pdf", "application/pdf", "starlight", fixtures.PDF(t, fixtures.Page{Text: "Native starlight observation record", JPEG: fixtures.JPEG(t, "Scanned glacier expedition notes")}, fixtures.Page{Text: "Second native document page"})},
	} {
		stored := api.upload(token, fixture.name, fixture.data, `{"title":"Imported record"}`, false, 202)
		storedID := stored["id"].(string)
		api.waitProcessing(token, storedID, "ready")
		api.assertMatch(token, fixture.query, storedID)
		if fixture.name == "mixed.pdf" {
			api.assertMatch(token, "glacier", storedID)
			api.assertMatch(token, "Second", storedID)
		}
		api.download(token, storedID, fixture.data, fixture.mediaType)
	}
	semantic := api.search(token, "semantic", "pay the household power bill")
	items := semantic["items"].([]any)
	if len(items) < 2 || items[0].(map[string]any)["document"].(map[string]any)["id"] != id {
		t.Fatalf("real embeddings did not rank the matching electricity document first: %v", semantic)
	}
	for _, item := range items {
		if item.(map[string]any)["document"].(map[string]any)["id"] == foreignID {
			t.Fatal("semantic search crossed namespaces")
		}
	}
	for _, query := range []string{"electrcity", "electricity invoice", "electrcity invoice", "pay the household power bill"} {
		combined := api.search(token, "hybrid", query)
		matches := combined["items"].([]any)
		if len(matches) == 0 || matches[0].(map[string]any)["document"].(map[string]any)["id"] != id {
			t.Fatalf("real hybrid typo/meaning recall for %q: %v", query, combined)
		}
		for _, match := range matches {
			if match.(map[string]any)["document"].(map[string]any)["id"] == foreignID {
				t.Fatal("hybrid search crossed namespaces")
			}
		}
	}
	priority := api.request(token, "POST", "/api/v1/documents", `{"title":"Electricity"}`, 201, "Document")
	combined := api.search(token, "hybrid", "electricity")
	if combined["items"].([]any)[0].(map[string]any)["document"].(map[string]any)["id"] != priority["id"] {
		t.Fatalf("metadata-only title did not outrank OCR: %v", combined)
	}
	filtered := api.request(token, "POST", "/api/v1/documents/search", `{"mode":"semantic","query":"household power bill","tags":["finance"],"limit":1}`, 200, "DocumentSearchResults")
	if filtered["total"] != nil || len(filtered["items"].([]any)) != 1 || filtered["items"].([]any)[0].(map[string]any)["document"].(map[string]any)["id"] != id {
		t.Fatalf("semantic tag filter lost its match or returned a fabricated total: %v", filtered)
	}
	api.request(token, "PATCH", "/api/v1/documents/"+id, `{"title":"Renamed ledger","sender":"New sender","subject":"","documentDate":"","tags":["archive"]}`, 200, "Document")
	api.assertMatch(token, "Renamed", id)
	if result := api.search(token, "fulltext", "settlement"); result["total"] != float64(0) {
		t.Fatal("cleared metadata remained in the full-text index")
	}
	api.assertMatch(token, "electricity", id)
	for _, invalid := range []string{`{}`, `{"sender":null}`, `{"tags":["Tag","tag"]}`, `{"documentDate":"2026-02-30"}`, `{"title":"A","title":"B"}`, `{"accountId":"foreign"}`} {
		api.request(token, "PATCH", "/api/v1/documents/"+id, invalid, 400, "Error")
	}
	for _, invalid := range []string{`{"mode":"semantic","query":""}`, `{"mode":"semantic","query":"x","limit":51}`, `{"mode":"semantic","query":"x","offset":10001}`, `{"mode":"semantic","query":"x","query":"y"}`} {
		api.request(token, "POST", "/api/v1/documents/search", invalid, 400, "Error")
	}
	api.upload(token, "unsupported.txt", []byte("not a supported document"), `{"title":"Unsupported"}`, false, 415)
	api.upload(token, "invalid-meta.png", png, `{"title":"Invalid","unknown":true}`, true, 400)
	broken := []byte("%PDF-1.7\nThis is a deliberately malformed PDF fixture.")
	failed := api.upload(token, "broken.pdf", broken, `{"title":"Broken original"}`, true, 202)
	failedID := failed["id"].(string)
	failedState := api.waitProcessing(token, failedID, "failed")
	if failedState["failureCode"] != "invalid_file" {
		t.Fatalf("malformed PDF exposed an unexpected error: %v", failedState)
	}
	api.download(token, failedID, broken, "application/pdf")
	api.upload(token, "broken-again.pdf", broken, `{"title":"Duplicate failed file"}`, false, 409)
	retried := api.request(token, "POST", "/api/v1/documents/"+failedID+"/retry", "", 202, "DocumentProcessing")
	if retried["generation"] != float64(2) {
		t.Fatal("retry did not advance the durable generation")
	}
	api.waitProcessing(token, failedID, "failed")

	concurrentBytes := fixtures.PNG(t, "Concurrent duplicate reservation", "Only one original belongs to this library.")
	uploadBody, uploadType, err := multipartDocument("concurrent.png", concurrentBytes, `{"title":"Concurrent original"}`, false)
	if err != nil {
		t.Fatal(err)
	}
	var wait sync.WaitGroup
	statuses := make(chan int, 2)
	accepted := make(chan string, 2)
	for range 2 {
		wait.Go(func() {
			status, _, data, err := api.send(token, "POST", "/api/v1/documents/upload", uploadType, bytes.NewReader(uploadBody))
			if err != nil {
				t.Error(err)
			}
			statuses <- status
			if status == 202 {
				var value map[string]any
				if json.Unmarshal(data, &value) == nil {
					accepted <- value["id"].(string)
				}
			}
		})
	}
	wait.Wait()
	first, second := <-statuses, <-statuses
	if !((first == 202 && second == 409) || (first == 409 && second == 202)) {
		t.Fatalf("concurrent duplicates were not serialized: %d %d", first, second)
	}
	api.waitProcessing(token, <-accepted, "ready")

	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	connection, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	var chunkCount, dimension int
	var extracted, digest string
	if err := connection.QueryRow(ctx, `SELECT count(*)::int,min(array_length(embedding,1)),string_agg(content,' '),min(model_digest) FROM document_chunks WHERE account_id=$1 AND document_id=$2 AND generation=1`, accountID, id).Scan(&chunkCount, &dimension, &extracted, &digest); err != nil {
		t.Fatal(err)
	}
	if chunkCount == 0 || dimension != 768 || !strings.Contains(strings.ToLower(extracted), "electricity") || len(digest) != 64 {
		t.Fatal("real extracted text and embeddings were not stored in PostgreSQL")
	}
	revocable := api.request("", "POST", "/api/v1/auth/login", `{"email":"upload-owner@example.test","password":"Document test password 2026!"}`, 200, "AuthSession")
	uploaderID := owner["identity"].(map[string]any)["user"].(map[string]any)["id"].(string)
	api.assertRevokedUploadCannotCommit(databaseURL, revocable["token"].(string), uploaderID)
	stop()
	api.baseURL, stop = startServer(t, binary, databaseURL, serverEnvironment)
	defer stop()
	api.download(token, id, png, "image/png")
	api.download(token, failedID, broken, "application/pdf")
	api.assertMatch(token, "electricity", id)
	api.assertMatch(token, "Renamed", id)
	retained := api.request(token, "GET", "/api/v1/system/document-processing", "", 200, "DocumentProcessingConfiguration")
	if retained["revision"] != configured["revision"] {
		t.Fatal("processing configuration did not survive restart")
	}
}
