//go:build e2e

package e2e_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	emailworkflows "github.com/domabas/domabas/backend/internal/domain/email/workflows"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/imapfixture"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	enumspb "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/client"
)

func emailJSON(t *testing.T, value any) string {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func (api *ingestionAPI) waitEmailRun(token, providerID, runID string) map[string]any {
	api.t.Helper()
	deadline := time.Now().Add(3 * time.Minute)
	for time.Now().Before(deadline) {
		var run map[string]any
		if runID != "" {
			run = api.request(token, "GET", "/api/v1/email-runs/"+runID, "", 200, "EmailRun")
		} else {
			page := api.request(token, "GET", "/api/v1/email-providers/"+providerID+"/runs", "", 200, "EmailRunPage")
			if items := page["items"].([]any); len(items) > 0 {
				run = items[0].(map[string]any)
			}
		}
		if run != nil && run["status"] != "queued" && run["status"] != "running" {
			return run
		}
		time.Sleep(150 * time.Millisecond)
	}
	api.t.Fatal("email retrieval did not finish before deadline")
	return nil
}

func cleanupOwnedEmail(t *testing.T, databaseURL, queue string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	db, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		t.Errorf("email cleanup database: %v", err)
		return
	}
	defer db.Close(ctx)
	var present bool
	if err = db.QueryRow(ctx, `SELECT to_regclass('email_executions') IS NOT NULL`).Scan(&present); err != nil || !present {
		return
	}
	rows, err := db.Query(ctx, `SELECT workflow_id,COALESCE(workflow_run_id,''),task_queue FROM email_executions`)
	if err != nil {
		t.Errorf("email cleanup identities: %v", err)
		return
	}
	type execution struct{ id, run, queue string }
	var executions []execution
	for rows.Next() {
		var value execution
		if err = rows.Scan(&value.id, &value.run, &value.queue); err != nil {
			break
		}
		executions = append(executions, value)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		t.Errorf("email cleanup identities: %v", err)
		return
	}
	if len(executions) == 0 {
		return
	}
	remote, err := client.DialContext(ctx, client.Options{HostPort: os.Getenv("TEMPORAL_ADDRESS"), Namespace: os.Getenv("TEMPORAL_NAMESPACE")})
	if err != nil {
		t.Errorf("email cleanup Temporal: %v", err)
		return
	}
	defer remote.Close()
	for _, value := range executions {
		info, err := remote.DescribeWorkflowExecution(ctx, value.id, value.run)
		var missing *serviceerror.NotFound
		if errors.As(err, &missing) {
			continue
		}
		if err != nil {
			t.Errorf("email cleanup describe: %v", err)
			continue
		}
		execution := info.GetWorkflowExecutionInfo()
		if value.queue != queue || execution.GetTaskQueue() != queue || execution.GetType().GetName() != emailworkflows.EmailPollWorkflowName {
			t.Error("email cleanup ownership mismatch; left untouched")
			continue
		}
		if execution.GetStatus() == enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING {
			if err = remote.TerminateWorkflow(ctx, value.id, execution.GetExecution().GetRunId(), "owned email API test cleanup"); err != nil && !errors.As(err, &missing) {
				t.Errorf("email cleanup terminate: %v", err)
			}
		}
	}
}

func TestEmailAPIEncryptedCredentialsScheduledImportConsentAndRetention(t *testing.T) {
	databaseURL := testdb.New(t)
	environment := newServerEnvironment(t, databaseURL)
	queue := ""
	for _, value := range environment {
		if strings.HasPrefix(value, "TEMPORAL_TASK_QUEUE=") {
			queue = strings.TrimPrefix(value, "TEMPORAL_TASK_QUEUE=") + "-email"
		}
	}
	t.Cleanup(func() { cleanupOwnedEmail(t, databaseURL, queue) })
	fixtureDirectory := filepath.Join(t.TempDir(), "imap")
	fixture, err := imapfixture.Start(fixtureDirectory, "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := fixture.Close(); err != nil {
			t.Error(err)
		}
	})
	environment = append(environment, "EMAIL_IMAP_ALLOWED_HOSTS=127.0.0.1", "EMAIL_IMAP_CA_FILE="+fixture.Ready.CAFile)
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
	base, stop := startServer(t, binary, databaseURL, environment)
	defer stop()
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 40 * time.Second}, spec: spec}
	register := func(email string) map[string]any {
		return api.request("", "POST", "/api/v1/auth/register", emailJSON(t, map[string]any{"accountName": "Email acceptance", "email": email, "password": "Email acceptance password 2026!"}), 201, "AuthSession")
	}
	owner := register("email-owner@example.test")
	token := owner["token"].(string)
	foreign := register("email-foreign@example.test")["token"].(string)
	if caps := api.request(token, "GET", "/api/v1/email-capabilities", "", 200, "EmailCapabilities"); caps["credentialsAvailable"] != true || caps["transport"] != "implicit_tls" {
		t.Fatalf("capabilities: %v", caps)
	}
	connection := map[string]any{"endpoint": fixture.Ready.Host, "port": fixture.Ready.Port, "mailbox": fixture.Ready.Mailbox, "username": fixture.Ready.Username, "password": fixture.Ready.Password}
	if tested := api.request(token, "POST", "/api/v1/email-connection-tests", emailJSON(t, connection), 200, "EmailConnectionTest"); tested["success"] != true {
		t.Fatalf("actual TLS connection test: %v", tested)
	}
	id := uuid.NewString()
	input := map[string]any{"id": id, "label": "Private fixture mailbox", "endpoint": fixture.Ready.Host, "port": fixture.Ready.Port, "mailbox": fixture.Ready.Mailbox, "username": fixture.Ready.Username, "password": fixture.Ready.Password, "intervalMinutes": 15, "maxAgeDays": 30, "pageSize": 1, "enabled": true}
	provider := api.request(token, "POST", "/api/v1/email-providers", emailJSON(t, input), 201, "EmailProvider")
	if provider["username"] != fixture.Ready.Username || provider["hasPassword"] != true || provider["consentState"] != "valid" {
		t.Fatalf("provider: %v", provider)
	}
	if _, exists := provider["password"]; exists {
		t.Fatal("password returned in provider")
	}
	db, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close(context.Background())
	var ciphertext []byte
	var keyID string
	if err = db.QueryRow(t.Context(), `SELECT credential_ciphertext,credential_key_id FROM email_providers WHERE id=$1`, id).Scan(&ciphertext, &keyID); err != nil {
		t.Fatal(err)
	}
	if keyID != "automatic" || len(ciphertext) < 35 || bytes.Contains(ciphertext, []byte(fixture.Ready.Username)) || bytes.Contains(ciphertext, []byte(fixture.Ready.Password)) {
		t.Fatal("login credentials not stored as authenticated ciphertext")
	}
	api.request(foreign, "GET", "/api/v1/email-providers/"+id, "", 404, "Error")
	for _, path := range []string{"/api/v1/email-providers?limit=0", "/api/v1/email-providers?cursor=", "/api/v1/email-providers?limit=1&limit=2"} {
		api.request(token, "GET", path, "", 400, "Error")
	}
	run := api.waitEmailRun(token, id, "")
	if run["status"] != "succeeded" || run["messagesAccepted"] != float64(1) || run["attachmentsAccepted"] != float64(2) || run["messagesWithContentFailures"] != float64(0) {
		t.Fatalf("real scheduled import: %v", run)
	}
	api.request(foreign, "GET", "/api/v1/email-runs/"+run["id"].(string), "", 404, "Error")
	jobPage := api.request(token, "GET", "/api/v1/email-runs", "", 200, "EmailRunPage")
	groups := jobPage["counts"].(map[string]any)["groups"].([]any)
	if len(groups) != 1 || groups[0].(map[string]any)["status"] != "succeeded" || groups[0].(map[string]any)["count"] != float64(1) {
		t.Fatalf("email totals missing: %v", groups)
	}
	foreignPage := api.request(foreign, "GET", "/api/v1/email-runs", "", 200, "EmailRunPage")
	if len(foreignPage["counts"].(map[string]any)["groups"].([]any)) != 0 {
		t.Fatal("email totals leaked another owner")
	}
	jobs := jobPage["items"].([]any)
	if len(jobs) != 1 || jobs[0].(map[string]any)["id"] != run["id"] || run["reason"] != "scheduled" {
		t.Fatalf("scheduled retrieval missing from jobs: %v", jobs)
	}
	if jobs := api.request(foreign, "GET", "/api/v1/email-runs", "", 200, "EmailRunPage")["items"].([]any); len(jobs) != 0 {
		t.Fatal("email jobs exposed another owner's history")
	}
	for _, path := range []string{"/api/v1/email-runs", "/api/v1/email-providers/" + id + "/runs"} {
		activePage := api.request(token, "GET", path+"?activeOnly=true", "", 200, "EmailRunPage")
		if len(activePage["items"].([]any)) != 0 || len(activePage["counts"].(map[string]any)["groups"].([]any)) != 1 {
			t.Fatalf("active email filter changed totals: %v", activePage)
		}
		items := api.request(token, "GET", path+"?status=succeeded&limit=1", "", 200, "EmailRunPage")["items"].([]any)
		if len(items) != 1 || items[0].(map[string]any)["id"] != run["id"] {
			t.Fatalf("successful run missing from filtered history: %v", items)
		}
		if items := api.request(token, "GET", path+"?status=failed", "", 200, "EmailRunPage")["items"].([]any); len(items) != 0 {
			t.Fatal("success included in failed filter")
		}
		for _, query := range []string{"status=unknown", "status=", "status=failed&status=succeeded", "activeOnly=unknown", "activeOnly=", "activeOnly=true&activeOnly=false"} {
			api.request(token, "GET", path+"?"+query, "", 400, "Error")
		}
	}
	api.request("", "GET", "/api/v1/email-runs", "", 401, "Error")
	for _, path := range []string{"/api/v1/email-runs?limit=0", "/api/v1/email-runs?cursor=", "/api/v1/email-runs?limit=1&limit=2", "/api/v1/email-runs?ownerId=" + id} {
		api.request(token, "GET", path, "", 400, "Error")
	}
	documents := api.request(token, "GET", "/api/v1/documents", "", 200, "DocumentList")["items"].([]any)
	if len(documents) != 3 {
		t.Fatalf("expected EML and two normal attachment documents: %d", len(documents))
	}
	var mail map[string]any
	for _, value := range documents {
		document := value.(map[string]any)
		if document["file"].(map[string]any)["mediaType"] == "message/rfc822" {
			mail = document
		}
		api.waitProcessing(token, document["id"].(string), "ready")
	}
	if mail == nil {
		t.Fatal("no raw EML document")
	}
	mailID := mail["id"].(string)
	status, headers, original, err := api.send(token, "GET", "/api/v1/documents/"+mailID+"/content", "", nil)
	api.decode(status, headers, original, err, 200, "")
	digest := sha256.Sum256(original)
	if mail["file"].(map[string]any)["sha256"] != hex.EncodeToString(digest[:]) || !bytes.Contains(original, []byte("Subject: Domabas email fixture\r\n")) {
		t.Fatal("raw EML identity changed")
	}
	processing := api.request(token, "GET", "/api/v1/documents/"+mailID+"/processing", "", 200, "DocumentProcessing")
	if processing["extractionMethod"] != "mime" || processing["ocrEngine"] != "domabas-mime" || processing["ocrModel"] != "" {
		t.Fatalf("invented OCR evidence for email: %v", processing)
	}
	api.assertMatch(token, "searchable body", mailID)
	links := api.request(token, "GET", "/api/v1/documents/"+mailID+"/email-links", "", 200, "DocumentEmailLinks")["attachments"].([]any)
	if len(links) != 2 {
		t.Fatalf("email attachment links: %v", links)
	}
	for _, value := range links {
		linked := value.(map[string]any)["document"].(map[string]any)["documentId"].(string)
		parents := api.request(token, "GET", "/api/v1/documents/"+linked+"/email-parents", "", 200, "DocumentEmailParents")["items"].([]any)
		if len(parents) != 1 || parents[0].(map[string]any)["documentId"] != mailID {
			t.Fatalf("source parents: %v", parents)
		}
	}
	stop()
	var keyPath string
	for _, entry := range environment {
		if strings.HasPrefix(entry, "EMAIL_CREDENTIAL_KEY_FILE=") {
			keyPath = strings.TrimPrefix(entry, "EMAIL_CREDENTIAL_KEY_FILE=")
		}
	}
	keyBefore, err := os.ReadFile(keyPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(keyPath, keyPath+".backup"); err != nil {
		t.Fatal(err)
	}
	assertEmailStartupFailure(t, binary, databaseURL, environment, "email credential key file is missing")
	if _, err := os.Stat(keyPath); !os.IsNotExist(err) {
		t.Fatal("missing retained email key regenerated", err)
	}
	if err := os.Rename(keyPath+".backup", keyPath); err != nil {
		t.Fatal(err)
	}
	base, stop = startServer(t, binary, databaseURL, environment)
	defer stop()
	api.baseURL = base
	if keyAfter, err := os.ReadFile(keyPath); err != nil || !bytes.Equal(keyBefore, keyAfter) {
		t.Fatal("email key changed after restart", err)
	}
	provider = api.request(token, "GET", "/api/v1/email-providers/"+id, "", 200, "EmailProvider")
	if provider["credentialState"] != "ready" || provider["username"] != fixture.Ready.Username {
		t.Fatal("automatic key did not restore email credentials after restart")
	}
	requestID := uuid.NewString()
	start := emailJSON(t, map[string]any{"requestId": requestID, "expectedRevision": provider["revision"]})
	manual := api.request(token, "POST", "/api/v1/email-providers/"+id+"/runs", start, 202, "EmailRun")
	replayed := api.request(token, "POST", "/api/v1/email-providers/"+id+"/runs", start, 202, "EmailRun")
	if replayed["id"] != manual["id"] {
		t.Fatal("manual retry duplicated run")
	}
	if second := api.waitEmailRun(token, id, manual["id"].(string)); second["status"] != "succeeded" {
		t.Fatalf("deduplicated second run: %v", second)
	}
	if count := len(api.request(token, "GET", "/api/v1/documents", "", 200, "DocumentList")["items"].([]any)); count != 3 {
		t.Fatalf("duplicate retrieval created %d documents", count)
	}
	activity := api.request(token, "GET", "/api/v1/auth/activity", "", 200, "PersonalActivity")
	if len(activity["finished"].([]any)) > 5 {
		t.Fatal("activity exceeded five terminal jobs")
	}
	foreignActivity := api.request(foreign, "GET", "/api/v1/auth/activity", "", 200, "PersonalActivity")
	if len(foreignActivity["active"].([]any))+len(foreignActivity["finished"].([]any)) != 0 {
		t.Fatal("foreign activity leaked jobs")
	}
	api.request(token, "PUT", "/api/v1/auth/password", `{"currentPassword":"Email acceptance password 2026!","newPassword":"Changed email account password 2026!"}`, 204, "")
	token = api.request("", "POST", "/api/v1/auth/login", `{"email":"email-owner@example.test","password":"Changed email account password 2026!"}`, 200, "AuthSession")["token"].(string)
	provider = api.request(token, "GET", "/api/v1/email-providers/"+id, "", 200, "EmailProvider")
	if provider["consentState"] != "renewal_required" {
		t.Fatalf("password reset did not revoke background consent: %v", provider)
	}
	delete(input, "id")
	delete(input, "username")
	delete(input, "password")
	input["expectedRevision"] = provider["revision"]
	provider = api.request(token, "PUT", "/api/v1/email-providers/"+id, emailJSON(t, input), 200, "EmailProvider")
	if provider["consentState"] != "renewal_required" {
		t.Fatal("no-op save renewed revoked consent")
	}
	api.request(token, "POST", "/api/v1/email-providers/"+id+"/runs", emailJSON(t, map[string]any{"requestId": uuid.NewString(), "expectedRevision": provider["revision"]}), 409, "Error")
	input["expectedRevision"] = provider["revision"]
	input["renewConsent"] = true
	provider = api.request(token, "PUT", "/api/v1/email-providers/"+id, emailJSON(t, input), 200, "EmailProvider")
	if provider["consentState"] != "valid" {
		t.Fatal("explicit renewal did not restore consent")
	}
	api.request(token, "DELETE", fmt.Sprintf("/api/v1/email-providers/%s?expectedRevision=%.0f", id, provider["revision"]), "", 204, "")
	api.request(token, "GET", "/api/v1/email-providers/"+id, "", 404, "Error")
	if jobs := api.request(token, "GET", "/api/v1/email-runs", "", 200, "EmailRunPage")["items"].([]any); len(jobs) < 2 {
		t.Fatal("deleted provider history missing from jobs")
	}
	api.download(token, mailID, original, "message/rfc822")
	var cleared bool
	if err = db.QueryRow(t.Context(), `SELECT credential_ciphertext IS NULL AND credential_key_id IS NULL FROM email_providers WHERE id=$1`, id).Scan(&cleared); err != nil || !cleared {
		t.Fatalf("provider deletion retained credentials: %v", err)
	}
	remote, err := client.DialContext(t.Context(), client.Options{HostPort: os.Getenv("TEMPORAL_ADDRESS"), Namespace: os.Getenv("TEMPORAL_NAMESPACE")})
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	history := remote.GetWorkflowHistory(t.Context(), "domabas-email-"+run["id"].(string), "", false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT)
	for history.HasNext() {
		event, err := history.Next()
		if err != nil {
			t.Fatal(err)
		}
		encoded := []byte(event.String())
		for _, secret := range []string{fixture.Ready.Username, fixture.Ready.Password, "searchable body and two attachments"} {
			if bytes.Contains(encoded, []byte(secret)) || bytes.Contains(encoded, []byte(base64.StdEncoding.EncodeToString([]byte(secret)))) {
				t.Fatal("workflow history contains mailbox secret/content")
			}
		}
	}
}
