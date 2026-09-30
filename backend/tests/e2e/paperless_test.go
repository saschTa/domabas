//go:build e2e

package e2e_test

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	enums "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/client"
)

func TestPaperlessDurableImportRestartDuplicatesFailuresIsolationAndPacing(t *testing.T) {
	databaseURL := testdb.New(t)
	environment := newServerEnvironment(t, databaseURL)
	original := fixtures.PNG(t, "Paperless migration invoice", "Amount due 120 euros")
	var mu sync.Mutex
	var requestTimes []time.Time
	var metadataRead bool
	var activeDownloads, maximumDownloads int
	fixture := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Error("source mutation attempted")
			w.WriteHeader(405)
			return
		}
		if r.Header.Get("Authorization") != "Token paperless-test-token" {
			w.WriteHeader(401)
			return
		}
		if r.Header.Get("Accept") != "application/json; version=9" {
			t.Error("wrong source API version")
		}
		mu.Lock()
		requestTimes = append(requestTimes, time.Now())
		firstRequest := len(requestTimes) == 1
		mu.Unlock()
		if firstRequest {
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/paperless/api/documents/":
			if r.URL.Query().Get("ordering") != "id" || r.URL.Query().Get("page_size") != "100" {
				t.Error("unbounded discovery")
			}
			if r.URL.Query().Get("page") == "1" {
				fmt.Fprint(w, `{"count":3,"next":"https://not-followed.example.test/steal-token","results":[{"id":1,"title":"Migration invoice"}]}`)
			} else {
				fmt.Fprint(w, `{"count":3,"next":null,"results":[{"id":2,"title":"Same original"},{"id":3,"title":"Unsupported"}]}`)
			}
		case "/paperless/api/documents/1/", "/paperless/api/documents/2/", "/paperless/api/documents/3/":
			var id int
			fmt.Sscanf(r.URL.Path, "/paperless/api/documents/%d/", &id)
			mu.Lock()
			metadataRead = true
			mu.Unlock()
			fmt.Fprintf(w, `{"id":%d,"title":"Migration invoice","created":"2026-09-18","original_file_name":"invoice.png","tags":[10],"correspondent":11,"document_type":12,"archive_serial_number":42}`, id)
		case "/paperless/api/tags/10/":
			fmt.Fprint(w, `{"id":10,"name":"Finance"}`)
		case "/paperless/api/correspondents/11/":
			fmt.Fprint(w, `{"id":11,"name":"Source utility"}`)
		case "/paperless/api/document_types/12/":
			fmt.Fprint(w, `{"id":12,"name":"Invoice"}`)
		case "/paperless/api/documents/1/download/", "/paperless/api/documents/2/download/":
			mu.Lock()
			activeDownloads++
			maximumDownloads = max(maximumDownloads, activeDownloads)
			mu.Unlock()
			defer func() { mu.Lock(); activeDownloads--; mu.Unlock() }()
			select {
			case <-r.Context().Done():
				return
			case <-time.After(2 * time.Second):
			}
			if r.URL.Query().Get("original") != "true" {
				t.Error("archive requested")
			}
			w.Header().Set("Content-Type", "image/png")
			w.Write(original)
		case "/paperless/api/documents/3/download/":
			w.Header().Set("Content-Type", "text/plain")
			fmt.Fprint(w, "unsupported file")
		default:
			http.NotFound(w, r)
		}
	}))
	defer fixture.Close()
	otherFixture := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" || r.Header.Get("Authorization") != "Token other-private-token" {
			t.Error("other user's source received incorrect credentials or method")
			w.WriteHeader(401)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/another/api/documents/":
			fmt.Fprintf(w, `{"count":1,"next":null,"results":[{"id":8,"title":%q}]}`, strings.Repeat("x", 1025))
		case "/another/api/documents/8/":
			fmt.Fprintf(w, `{"id":8,"title":%q,"created":"2026-09-19","original_file_name":"invoice.png","tags":[]}`, strings.Repeat("x", 1025))
		case "/another/api/documents/8/download/":
			w.Header().Set("Content-Type", "image/png")
			w.Write(original)
		default:
			http.NotFound(w, r)
		}
	}))
	defer otherFixture.Close()
	binary := filepath.Join(t.TempDir(), "server")
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v %s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	base, stop := startServer(t, binary, databaseURL, environment)
	var keyPath string
	for _, value := range environment {
		if strings.HasPrefix(value, "PAPERLESS_CREDENTIAL_KEY_FILE=") {
			keyPath = strings.TrimPrefix(value, "PAPERLESS_CREDENTIAL_KEY_FILE=")
		}
	}
	initialKey, err := os.ReadFile(keyPath)
	if err != nil || len(initialKey) == 0 {
		t.Fatal("first startup did not provision its key", err)
	}
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 20 * time.Second}, spec: spec}
	register := func(email string) map[string]any {
		return api.request("", "POST", "/api/v1/auth/register", emailJSON(t, map[string]any{"accountName": "Paperless test", "email": email, "password": "Paperless test password 2026!"}), 201, "AuthSession")
	}
	owner := register("paperless-owner@example.test")
	other := register("paperless-other@example.test")
	token, otherToken := owner["token"].(string), other["token"].(string)
	api.request("", "GET", "/api/v1/system/paperless-import", "", 401, "Error")
	api.request(otherToken, "GET", "/api/v1/system/paperless-import", "", 403, "Error")
	api.request(otherToken, "PUT", "/api/v1/system/paperless-import", `{"retrievalConcurrency":3,"expectedRevision":1}`, 403, "Error")
	settings := api.request(token, "GET", "/api/v1/system/paperless-import", "", 200, "PaperlessSettings")
	if settings["retrievalConcurrency"] != float64(1) || settings["revision"] != float64(1) {
		t.Fatal(settings)
	}
	for _, body := range []string{`{"retrievalConcurrency":11,"expectedRevision":1}`, `{"retrievalConcurrency":1,"expectedRevision":null}`, `{"retrievalConcurrency":1,"retrievalConcurrency":2,"expectedRevision":1}`, `{"retrievalConcurrency":1,"expectedRevision":1,"unknown":true}`} {
		api.request(token, "PUT", "/api/v1/system/paperless-import", body, 400, "Error")
	}
	settings = api.request(token, "PUT", "/api/v1/system/paperless-import", `{"retrievalConcurrency":3,"expectedRevision":1}`, 200, "PaperlessSettings")
	if settings["retrievalConcurrency"] != float64(3) || settings["revision"] != float64(2) {
		t.Fatal(settings)
	}
	api.request(token, "PUT", "/api/v1/system/paperless-import", `{"retrievalConcurrency":2,"expectedRevision":1}`, 409, "Error")
	api.request("", "GET", "/api/v1/paperless-import", "", 401, "Error")
	options := api.request(token, "GET", "/api/v1/paperless-import", "", 200, "PaperlessOptions")
	if options["pageSize"] != float64(100) || len(options) != 1 {
		t.Fatal(options)
	}
	api.request(token, "POST", "/api/v1/paperless-import/runs", `{"serverUrl":"x","token":"one","token":"two","requestId":"`+uuid.NewString()+`"}`, 400, "Error")
	for _, server := range []string{"file:///etc/passwd", "http://169.254.169.254", "http://[::]", "http://paperless.example.test?token=secret", "http://user:secret@paperless.example.test"} {
		api.request(token, "POST", "/api/v1/paperless-import/runs", emailJSON(t, map[string]any{"serverUrl": server, "token": "token", "requestId": uuid.NewString()}), 422, "Error")
	}
	id := uuid.NewString()
	body := emailJSON(t, map[string]any{"requestId": id, "serverUrl": fixture.URL + "/paperless", "token": "paperless-test-token"})
	api.request(token, "POST", "/api/v1/paperless-import/runs", body, 202, "PaperlessRun")
	api.request(token, "POST", "/api/v1/paperless-import/runs", body, 202, "PaperlessRun")
	api.request(otherToken, "GET", "/api/v1/paperless-import/runs/"+id, "", 404, "Error")
	api.request(otherToken, "POST", "/api/v1/paperless-import/runs/"+id+"/cancel", "", 404, "Error")
	otherID := uuid.NewString()
	api.request(otherToken, "POST", "/api/v1/paperless-import/runs", emailJSON(t, map[string]any{"requestId": otherID, "serverUrl": otherFixture.URL + "/another/", "token": "other-private-token"}), 202, "PaperlessRun")
	api.request(token, "GET", "/api/v1/paperless-import/runs/"+otherID, "", 404, "Error")
	for _, owned := range []struct{ token, id string }{{token, id}, {otherToken, otherID}} {
		page := api.request(owned.token, "GET", "/api/v1/paperless-import/runs", "", 200, "PaperlessRunPage")
		items := page["items"].([]any)
		if len(items) != 1 || items[0].(map[string]any)["id"] != owned.id || strings.Contains(fmt.Sprint(page), "private-token") || strings.Contains(fmt.Sprint(page), "paperless-test-token") {
			t.Fatal("connection credentials or another user's run disclosed", page)
		}
	}
	db, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close(context.Background())
	var encrypted []byte
	if err := db.QueryRow(t.Context(), "SELECT encrypted_token FROM paperless_runs WHERE id=$1", id).Scan(&encrypted); err != nil || bytes.Contains(encrypted, []byte("paperless-test-token")) {
		t.Fatal("plaintext token", err)
	}
	deadline := time.Now().Add(time.Minute)
	for time.Now().Before(deadline) {
		mu.Lock()
		seen := metadataRead
		mu.Unlock()
		if seen {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	mu.Lock()
	seen := metadataRead
	mu.Unlock()
	if !seen {
		t.Fatal("Temporal did not begin import")
	}
	stop()
	base, stop = startServer(t, binary, databaseURL, environment)
	api.baseURL = base
	retainedKey, err := os.ReadFile(keyPath)
	if err != nil || !bytes.Equal(retainedKey, initialKey) {
		t.Fatal("startup rotated active import credentials", err)
	}
	wait := func(session, id string) map[string]any {
		t.Helper()
		deadline := time.Now().Add(3 * time.Minute)
		for time.Now().Before(deadline) {
			r := api.request(session, "GET", "/api/v1/paperless-import/runs/"+id, "", 200, "PaperlessRun")
			if r["state"] != "queued" && r["state"] != "running" {
				return r
			}
			time.Sleep(200 * time.Millisecond)
		}
		t.Fatal("durable import did not finish")
		return nil
	}
	result := wait(token, id)
	settings = api.request(token, "GET", "/api/v1/system/paperless-import", "", 200, "PaperlessSettings")
	if settings["retrievalConcurrency"] != float64(3) || settings["revision"] != float64(2) {
		t.Fatal("settings lost on restart", settings)
	}
	if result["state"] != "succeeded" || result["imported"] != float64(1) || result["duplicates"] != float64(1) || result["failed"] != float64(1) || result["discovered"] != float64(3) {
		t.Fatal(result)
	}
	mu.Lock()
	if maximumDownloads < 2 {
		t.Errorf("one import never overlapped original downloads: maximum %d", maximumDownloads)
	}
	if len(requestTimes) < 2 || requestTimes[1].Sub(requestTimes[0]) < 9*time.Second {
		t.Error("source overload was retried without backoff")
	}
	for i := 1; i < len(requestTimes); i++ {
		if requestTimes[i].Sub(requestTimes[i-1]) < 95*time.Millisecond {
			t.Errorf("source overload: interval %s", requestTimes[i].Sub(requestTimes[i-1]))
		}
	}
	mu.Unlock()
	var documentID string
	for _, v := range result["outcomes"].([]any) {
		o := v.(map[string]any)
		if o["status"] == "imported" {
			documentID = o["documentId"].(string)
		}
	}
	doc := api.request(token, "GET", "/api/v1/documents/"+documentID, "", 200, "Document")
	if doc["title"] != "Migration invoice" || doc["sender"] != "Source utility" || doc["documentDate"] != "2026-09-18" || !strings.Contains(doc["description"].(string), "Archive serial number: 42") {
		t.Fatal(doc)
	}
	api.download(token, documentID, original, "image/png")
	api.waitProcessing(token, documentID, "ready")
	otherResult := wait(otherToken, otherID)
	if otherResult["state"] != "succeeded" || otherResult["imported"] != float64(1) || otherResult["serverUrl"] != otherFixture.URL+"/another" {
		t.Fatal("second user could not import their own server", otherResult)
	}
	otherDocumentID := otherResult["outcomes"].([]any)[0].(map[string]any)["documentId"].(string)
	otherDocument := api.request(otherToken, "GET", "/api/v1/documents/"+otherDocumentID, "", 200, "Document")
	if otherDocument["title"] != "Paperless document 8" || otherDocument["description"] != "Imported from Paperless: "+otherFixture.URL+"/another/documents/8/details" || otherDocument["kind"] != "document" || len(otherDocument["tags"].([]any)) != 0 {
		t.Fatal(otherDocument)
	}
	for _, field := range []string{"sender", "documentDate"} {
		if value := otherDocument[field]; value != nil && value != "" {
			t.Fatalf("fallback retained %s: %v", field, value)
		}
	}
	api.request(token, "GET", "/api/v1/documents/"+otherDocumentID, "", 404, "Error")
	api.request(otherToken, "GET", "/api/v1/documents/"+documentID, "", 404, "Error")
	api.download(otherToken, otherDocumentID, original, "image/png")
	api.waitProcessing(otherToken, otherDocumentID, "ready")
	if err := db.QueryRow(t.Context(), "SELECT encrypted_token FROM paperless_runs WHERE id=$1", id).Scan(&encrypted); err != nil || encrypted != nil {
		t.Fatal("token retained", err)
	}
	for _, item := range []struct {
		token    string
		expected string
	}{{"bad-token", "failed"}, {"paperless-test-token", "cancelled"}} {
		runID := uuid.NewString()
		api.request(token, "POST", "/api/v1/paperless-import/runs", emailJSON(t, map[string]any{"requestId": runID, "serverUrl": fixture.URL + "/paperless", "token": item.token}), 202, "PaperlessRun")
		if item.expected == "cancelled" {
			api.request(token, "POST", "/api/v1/paperless-import/runs/"+runID+"/cancel", "", 200, "PaperlessRun")
		}
		if r := wait(token, runID); r["state"] != item.expected {
			t.Fatal(r)
		}
	}
	assertPaperlessPagination(t, api, db, token, otherToken, id)
	stop()
}

func cleanupOwnedPaperless(t *testing.T, databaseURL, queue string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	db, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		t.Error(err)
		return
	}
	defer db.Close(ctx)
	var present bool
	if err = db.QueryRow(ctx, "SELECT to_regclass('paperless_runs') IS NOT NULL").Scan(&present); err != nil || !present {
		return
	}
	rows, err := db.Query(ctx, "SELECT id,task_queue FROM paperless_runs WHERE NOT execution_closed")
	if err != nil {
		t.Error(err)
		return
	}
	var ids []string
	for rows.Next() {
		var id, storedQueue string
		if err = rows.Scan(&id, &storedQueue); err != nil {
			break
		}
		if storedQueue != queue+"-paperless" {
			t.Error("foreign Paperless queue left untouched")
			continue
		}
		ids = append(ids, id)
	}
	err = errors.Join(err, rows.Err())
	rows.Close()
	if err != nil {
		t.Error(err)
		return
	}
	if len(ids) == 0 {
		return
	}
	remote, err := client.DialContext(ctx, client.Options{HostPort: os.Getenv("TEMPORAL_ADDRESS"), Namespace: os.Getenv("TEMPORAL_NAMESPACE")})
	if err != nil {
		t.Error(err)
		return
	}
	defer remote.Close()
	for _, id := range ids {
		workflowID := "domabas-paperless-" + id
		info, err := remote.DescribeWorkflowExecution(ctx, workflowID, "")
		var missing *serviceerror.NotFound
		if errors.As(err, &missing) {
			continue
		}
		if err != nil {
			t.Error(err)
			continue
		}
		e := info.GetWorkflowExecutionInfo()
		if e.GetTaskQueue() != queue+"-paperless" || e.GetType().GetName() != "domabas.PaperlessImport.v1" {
			t.Error("foreign execution left untouched")
			continue
		}
		if e.GetStatus() == enums.WORKFLOW_EXECUTION_STATUS_RUNNING {
			if err := remote.TerminateWorkflow(ctx, workflowID, e.GetExecution().GetRunId(), "owned Paperless API test cleanup"); err != nil {
				t.Error(err)
			}
		}
	}
}

func assertPaperlessPagination(t *testing.T, api *ingestionAPI, db *pgx.Conn, token, otherToken, id string) {
	t.Helper()
	if _, err := db.Exec(t.Context(), "INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,task_queue,state,stage,execution_closed,created_at) SELECT gen_random_uuid(),account_id,owner_id,credential_revision,server_url,request_hash,task_queue,'succeeded','complete',true,'2000-01-01' FROM paperless_runs CROSS JOIN generate_series(1,25) WHERE id=$1", id); err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	cursor := ""
	for {
		page := api.request(token, "GET", "/api/v1/paperless-import/runs?limit=20"+cursor, "", 200, "PaperlessRunPage")
		items := page["items"].([]any)
		if len(items) > 20 {
			t.Fatal("unbounded imports")
		}
		for _, item := range items {
			value := item.(map[string]any)
			if seen[value["id"].(string)] || len(value["outcomes"].([]any)) != 0 {
				t.Fatal("repeated import or eager outcomes", value)
			}
			seen[value["id"].(string)] = true
		}
		next, _ := page["nextCursor"].(string)
		if next == "" {
			break
		}
		cursor = "&cursor=" + url.QueryEscape(next)
	}
	if len(seen) != 28 {
		t.Fatal("incomplete run history", len(seen))
	}
	succeeded := api.request(token, "GET", "/api/v1/paperless-import/runs?status=succeeded&limit=1", "", 200, "PaperlessRunPage")
	groups := succeeded["counts"].(map[string]any)["groups"].([]any)
	var total float64
	for _, item := range groups {
		total += item.(map[string]any)["count"].(float64)
	}
	if total != 28 {
		t.Fatalf("Paperless totals followed filter/page: %v", groups)
	}
	items := succeeded["items"].([]any)
	if len(items) != 1 || items[0].(map[string]any)["state"] != "succeeded" || items[0].(map[string]any)["failed"] != float64(0) {
		t.Fatalf("incorrect success filter: %v", succeeded)
	}
	filteredCursor := url.QueryEscape(succeeded["nextCursor"].(string))
	api.request(token, "GET", "/api/v1/paperless-import/runs?status=succeeded&limit=1&cursor="+filteredCursor, "", 200, "PaperlessRunPage")
	api.request(token, "GET", "/api/v1/paperless-import/runs?status=failed&limit=1&cursor="+filteredCursor, "", 400, "Error")
	for _, query := range []string{"limit=0", "limit=101", "cursor=", "cursor=invalid", "limit=20&limit=20", "unknown=true", "status=unknown", "status=", "status=failed&status=succeeded"} {
		api.request(token, "GET", "/api/v1/paperless-import/runs?"+query, "", 400, "Error")
	}
	if _, err := db.Exec(t.Context(), "INSERT INTO paperless_items(run_id,source_id,title,status) SELECT $1,n,'Older result','failed' FROM generate_series(1000,1114) n", id); err != nil {
		t.Fatal(err)
	}
	partialPage := api.request(token, "GET", "/api/v1/paperless-import/runs?status=partial", "", 200, "PaperlessRunPage")
	var partialTotal float64
	for _, item := range partialPage["counts"].(map[string]any)["groups"].([]any) {
		group := item.(map[string]any)
		if group["status"] == "partial" {
			partialTotal = group["count"].(float64)
		}
	}
	if partialTotal != 1 {
		t.Fatalf("Paperless effective partial total missing: %v", partialPage)
	}
	partial := partialPage["items"].([]any)
	if len(partial) != 1 || partial[0].(map[string]any)["id"] != id {
		t.Fatalf("partial import missing: %v", partial)
	}
	path := "/api/v1/paperless-import/runs/" + id + "/outcomes"
	api.request(otherToken, "GET", path, "", 404, "Error")
	api.request("", "GET", path, "", 401, "Error")
	cursor = ""
	count := 0
	last := float64(2000)
	for {
		page := api.request(token, "GET", path+"?limit=20"+cursor, "", 200, "PaperlessOutcomePage")
		items := page["items"].([]any)
		if len(items) > 20 {
			t.Fatal("unbounded outcomes")
		}
		for _, item := range items {
			value := item.(map[string]any)["sourceId"].(float64)
			if value >= last {
				t.Fatal("outcome order")
			}
			last = value
			count++
		}
		next, _ := page["nextCursor"].(string)
		if next == "" {
			break
		}
		cursor = "&cursor=" + url.QueryEscape(next)
	}
	if count != 118 {
		t.Fatal("incomplete outcomes", count)
	}
	if _, err := db.Exec(t.Context(), "INSERT INTO paperless_items(run_id,source_id,title,status) SELECT $1,n,'Newer imported result','imported' FROM generate_series(2000,2030) n", id); err != nil {
		t.Fatal(err)
	}
	all := api.request(token, "GET", path+"?limit=20", "", 200, "PaperlessOutcomePage")
	for _, item := range all["items"].([]any) {
		if item.(map[string]any)["status"] != "imported" {
			t.Fatal("expected failures outside first unfiltered page")
		}
	}
	failed := api.request(token, "GET", path+"?status=failed&limit=20", "", 200, "PaperlessOutcomePage")
	failedCursor := url.QueryEscape(failed["nextCursor"].(string))
	api.request(token, "GET", path+"?limit=20&cursor="+failedCursor, "", 400, "Error")
	api.request(token, "GET", path+"?status=imported&limit=20&cursor="+failedCursor, "", 400, "Error")
	api.request(token, "GET", path+"?status=failed&limit=20&cursor="+url.QueryEscape(all["nextCursor"].(string)), "", 400, "Error")
	api.request(otherToken, "GET", path+"?status=failed&limit=20&cursor="+failedCursor, "", 404, "Error")
	filteredCount := 0
	for {
		for _, item := range failed["items"].([]any) {
			if item.(map[string]any)["status"] != "failed" {
				t.Fatal("unexpected status in filtered outcomes", item)
			}
			filteredCount++
		}
		next, _ := failed["nextCursor"].(string)
		if next == "" {
			break
		}
		failed = api.request(token, "GET", path+"?status=failed&limit=20&cursor="+url.QueryEscape(next), "", 200, "PaperlessOutcomePage")
	}
	if filteredCount != 116 {
		t.Fatal("incomplete failed outcomes", filteredCount)
	}
	for _, query := range []string{"status=unknown", "status=", "status=pending", "status=succeeded", "status=failed&status=imported"} {
		api.request(token, "GET", path+"?"+query, "", 400, "Error")
	}
	api.request(token, "GET", path+"?cursor=invalid", "", 400, "Error")
	for _, query := range []string{"activeCursor=", "finishedCursor=invalid", "activeCursor=x&activeCursor=y", "unknown=true"} {
		api.request(token, "GET", "/api/v1/auth/activity?"+query, "", 400, "Error")
	}
}
