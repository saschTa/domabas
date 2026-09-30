//go:build e2e

package e2e_test

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestAIChatIndependentSettingsToolsPrivacyRecoveryAndResourceAdmission(t *testing.T) {
	databaseURL := testdb.New(t)
	env := newServerEnvironment(t, databaseURL)
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
	var externalCalls atomic.Int32
	var externalHold atomic.Bool
	externalStarted := make(chan struct{}, 8)
	externalContentionCancelled := make(chan struct{}, 1)
	fixtureStop := make(chan struct{})
	var documentID string
	var providerDocumentID atomic.Value
	providerDocumentID.Store("")
	var scannedDocumentID atomic.Value
	scannedDocumentID.Store("")
	var budgetProviderCalls atomic.Int32
	external := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "Bearer chat-test-secret" {
			w.WriteHeader(401)
			return
		}
		var request struct {
			Model           string `json:"model"`
			ReasoningEffort string `json:"reasoning_effort"`
			Messages        []struct {
				Role, Content string
				ToolCallID    string `json:"tool_call_id"`
			} `json:"messages"`
			Tools      []any  `json:"tools"`
			ToolChoice string `json:"tool_choice"`
		}
		if json.NewDecoder(r.Body).Decode(&request) != nil || request.Model != "chat-model" || request.ReasoningEffort != "medium" || (len(request.Tools) != 3 && request.ToolChoice != "none") {
			w.WriteHeader(400)
			return
		}
		externalCalls.Add(1)
		externalContention := false
		for _, message := range request.Messages {
			if message.Role == "user" {
				externalContention = strings.HasPrefix(message.Content, "External resource test:")
			}
		}
		if externalHold.Load() {
			select {
			case externalStarted <- struct{}{}:
			default:
			}
			ticker := time.NewTicker(20 * time.Millisecond)
			defer ticker.Stop()
			for externalHold.Load() {
				select {
				case <-r.Context().Done():
					if externalContention {
						externalContentionCancelled <- struct{}{}
					}
					return
				case <-fixtureStop:
					return
				case <-ticker.C:
				}
			}
		}
		if externalContention {
			_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "stop", "message": map[string]any{"role": "assistant", "content": "External inference completed without interruption."}}}})
			return
		}
		currentDocumentID := providerDocumentID.Load().(string)
		currentScannedID := scannedDocumentID.Load().(string)
		results := []string{}
		stress := false
		guarded := false
		lastCallID := ""
		for _, message := range request.Messages {
			if message.Role == "user" {
				guarded = strings.Contains(message.Content, "Deterministic guarded retrieval")
			}
			if message.Role == "user" && strings.Contains(message.Content, "Deterministic thirty-call budget stress") {
				stress = true
			}
			if message.Role == "tool" {
				results = append(results, message.Content)
				lastCallID = message.ToolCallID
			}
		}
		tool := func(id, name string, args any) {
			body, _ := json.Marshal(args)
			_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "tool_calls", "message": map[string]any{"role": "assistant", "content": "", "tool_calls": []any{map[string]any{"id": id, "type": "function", "function": map[string]any{"name": name, "arguments": string(body)}}}}}}})
		}
		answer := func() {
			readText, readScan := false, false
			for _, result := range results {
				var document struct {
					DocumentID string `json:"documentId"`
					Text       string `json:"text"`
				}
				if json.Unmarshal([]byte(result), &document) == nil {
					readText = readText || document.DocumentID == currentDocumentID && strings.Contains(document.Text, "42 euros")
					readScan = readScan || document.DocumentID == currentScannedID && strings.Contains(document.Text, "73 euros")
				}
			}
			if !readText || !readScan {
				t.Error("PDF reads omitted expected extracted amounts", readText, readScan)
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "stop", "message": map[string]any{"role": "assistant", "content": "The text PDF records 42 euros; the scanned PDF records 73 euros."}}}})
		}
		if guarded {
			switch len(results) {
			case 0:
				tool("guard-search", "search_documents", map[string]any{"query": "Chat evidence", "offset": 0})
			case 1:
				tool("guard-read", "read_document", map[string]any{"documentId": currentDocumentID, "offset": 0})
			case 2:
				tool("guard-repeat", "search_documents", map[string]any{"query": "Chat evidence", "offset": 0})
			case 3:
				tool("guard-invented", "read_document", map[string]any{"documentId": "d34a9999-9999-4444-aaff-999999999999", "offset": 0})
			case 4:
				tool("guard-offset", "search_documents", map[string]any{"query": "Chat evidence", "offset": 10})
			default:
				if request.ToolChoice != "none" || len(results) != 5 {
					t.Error("no-progress turn did not stop after three rejected attempts", len(results), request.ToolChoice)
				}
				tool("guard-ignored-stop", "search_documents", map[string]any{"query": "Chat evidence", "offset": 0})
			}
			return
		}
		if stress {
			budgetProviderCalls.Add(1)
			completed := 0
			if lastCallID != "" {
				var err error
				completed, err = strconv.Atoi(strings.TrimPrefix(lastCallID, "budget-"))
				if err != nil {
					t.Error("budget stress lost persisted call identity", lastCallID)
					w.WriteHeader(400)
					return
				}
			}
			id := fmt.Sprintf("budget-%d", completed+1)
			switch {
			case completed < 2:
				tool(id, "list_tools", map[string]any{"offset": completed * 2})
			case completed < 27:
				tool(id, "search_documents", map[string]any{"query": fmt.Sprintf("BudgetEvidence%d", completed-2), "offset": 0})
			case completed == 27:
				tool(id, "search_documents", map[string]any{"query": "Chat evidence", "offset": 0})
			case completed == 28:
				tool(id, "read_document", map[string]any{"documentId": currentDocumentID, "offset": 0})
			case completed == 29:
				tool(id, "read_document", map[string]any{"documentId": currentScannedID, "offset": 0})
			case completed == 30:
				if request.ToolChoice != "none" {
					t.Error("exhausted tool budget did not request an answer-only response")
				}
				answer()
			default:
				t.Error("provider exceeded thirty tool calls", completed)
				w.WriteHeader(400)
			}
			return
		}
		switch len(results) {
		case 0:
			tool("catalog-1", "list_tools", map[string]any{"offset": 0})
		case 1:
			var page struct {
				Items      []json.RawMessage `json:"items"`
				NextOffset *int              `json:"nextOffset"`
			}
			if json.Unmarshal([]byte(results[0]), &page) != nil || len(page.Items) != 2 || page.NextOffset == nil || *page.NextOffset != 2 {
				t.Error("tool catalog did not return bounded continuation", results[0])
				w.WriteHeader(400)
				return
			}
			tool("catalog-2", "list_tools", map[string]any{"offset": *page.NextOffset})
		case 2:
			if !strings.Contains(strings.Join(results, " "), "read_document") || !strings.Contains(strings.Join(results, " "), "search_documents") {
				t.Error("catalog did not describe available document tools")
			}
			tool("search-1", "search_documents", map[string]any{"query": "Chat evidence", "offset": 0})
		case 3:
			if !strings.Contains(results[2], currentDocumentID) || !strings.Contains(results[2], currentScannedID) {
				t.Error("search tool omitted authorized document")
			}
			tool("read-1", "read_document", map[string]any{"documentId": currentDocumentID, "offset": 0})
		case 4:
			tool("read-2", "read_document", map[string]any{"documentId": currentScannedID, "offset": 0})
		default:
			answer()
		}
	}))
	defer external.Close()
	var internalHold atomic.Bool
	internalStarted := make(chan struct{}, 8)
	internalCancelled := make(chan struct{}, 8)
	ollama := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.Copy(io.Discard, r.Body)
		switch r.URL.Path {
		case "/api/tags":
			_ = json.NewEncoder(w).Encode(map[string]any{"models": []any{map[string]any{"name": "qwen3.5:4b"}, map[string]any{"name": "another-model"}}})
		case "/api/show":
			_, _ = w.Write([]byte(`{"capabilities":["completion"],"model_info":{"general.architecture":"qwen35","qwen35.context_length":131072}}`))
		case "/api/chat":
			if internalHold.Load() {
				select {
				case internalStarted <- struct{}{}:
				default:
				}
				select {
				case <-r.Context().Done():
				case <-fixtureStop:
				}
				select {
				case internalCancelled <- struct{}{}:
				default:
				}
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]any{"role": "assistant", "content": `{"action":"answer","content":"Internal reply completed.","query":"","documentId":"","offset":0}`}})
		default:
			w.WriteHeader(404)
		}
	}))
	defer ollama.Close()
	defer close(fixtureStop)
	env = append(env, "LLM_OLLAMA_URL="+ollama.URL)
	base, stop := startServer(t, binary, databaseURL, env)
	defer func() { stop() }()
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 15 * time.Second}, spec: spec}
	admin := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Chat library","email":"chat-admin@example.test","password":"Chat test password 2026!"}`, 201, "AuthSession")["token"].(string)
	other := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Other chat library","email":"chat-other@example.test","password":"Chat test password 2026!"}`, 201, "AuthSession")["token"].(string)
	settingsPath := "/api/v1/system/chat/configuration"
	api.request(other, "GET", settingsPath, "", 403, "Error")
	api.request(other, "PUT", settingsPath, "{", 403, "Error")
	settings := api.request(admin, "GET", settingsPath, "", 200, "ChatConfiguration")
	if settings["model"] != "qwen3.5:4b" || settings["enabled"] != true || settings["hasApiKey"] != false || settings["thinkingEnabled"] != false {
		t.Fatal("chat defaults", settings)
	}
	pipeline := api.request(admin, "GET", "/api/v1/system/document-processing", "", 200, "DocumentProcessingConfiguration")
	update := func(provider, model, url, key string) map[string]any {
		body := map[string]any{"expectedRevision": settings["revision"], "enabled": true, "provider": provider, "model": model, "baseUrl": url, "apiKey": nil, "clearApiKey": nil, "thinkingEnabled": true}
		if key != "" {
			body["apiKey"] = key
		}
		encoded, _ := json.Marshal(body)
		settings = api.request(admin, "PUT", settingsPath, string(encoded), 200, "ChatConfiguration")
		return settings
	}
	update("openai", "chat-model", external.URL+"/v1", "chat-test-secret")
	previousRevision := settings["revision"]
	update("openai", "chat-model", external.URL+"/v1", "")
	if settings["hasApiKey"] != true || settings["revision"] != previousRevision {
		t.Fatal("nullable credential options did not preserve settings")
	}
	if externalCalls.Load() != 0 {
		t.Fatal("settings save made inference")
	}
	encoded, _ := json.Marshal(settings)
	if strings.Contains(string(encoded), "chat-test-secret") || settings["hasApiKey"] != true {
		t.Fatal("secret disclosure", string(encoded))
	}
	unchanged := api.request(admin, "GET", "/api/v1/system/document-processing", "", 200, "DocumentProcessingConfiguration")
	if unchanged["revision"] != pipeline["revision"] {
		t.Fatal("chat changed document pipeline")
	}
	summary := api.request(other, "GET", "/api/v1/chat/configuration", "", 200, "ChatConfigurationSummary")
	encoded, _ = json.Marshal(summary)
	if strings.Contains(string(encoded), external.URL) || strings.Contains(string(encoded), "hasApiKey") {
		t.Fatal("public settings exposed connection")
	}
	for _, invalid := range []string{`null`, `{}`, `{"requestId":null}`, `{"requestId":"bad","requestId":"bad"}`} {
		api.request(admin, "POST", "/api/v1/chat/conversations", invalid, 400, "Error")
	}
	createID := uuid.NewString()
	createBody := fmt.Sprintf(`{"requestId":%q}`, createID)
	conversation := api.request(admin, "POST", "/api/v1/chat/conversations", createBody, 201, "ChatConversation")
	id := conversation["id"].(string)
	if api.request(admin, "POST", "/api/v1/chat/conversations", createBody, 201, "ChatConversation")["id"] != id {
		t.Fatal("create retry duplicated")
	}
	path := "/api/v1/chat/conversations/" + id
	api.request(other, "GET", path, "", 404, "Error")
	api.request(other, "GET", path+"/messages", "", 404, "Error")
	for range 2 {
		api.request(admin, "POST", "/api/v1/chat/conversations", fmt.Sprintf(`{"requestId":%q}`, uuid.NewString()), 201, "ChatConversation")
	}
	historyIDs := map[string]bool{}
	historyCursor := ""
	for range 3 {
		historyPath := "/api/v1/chat/conversations?limit=1"
		if historyCursor != "" {
			historyPath += "&cursor=" + historyCursor
		}
		page := api.request(admin, "GET", historyPath, "", 200, "ChatConversationPage")
		items := page["items"].([]any)
		if len(items) != 1 {
			t.Fatal("conversation continuation lost a page", page)
		}
		pageID := items[0].(map[string]any)["id"].(string)
		if historyIDs[pageID] {
			t.Fatal("conversation continuation repeated a record", pageID)
		}
		historyIDs[pageID] = true
		historyCursor, _ = page["nextCursor"].(string)
	}
	if len(historyIDs) != 3 || !historyIDs[id] || historyCursor != "" {
		t.Fatal("conversation pagination did not reach all records", historyIDs, historyCursor)
	}
	doc := api.upload(admin, "chat-text.pdf", fixtures.PDF(t, fixtures.Page{Text: "Chat evidence amount 42 euros"}), `{"title":"Chat evidence text PDF"}`, true, 202)
	documentID = doc["id"].(string)
	providerDocumentID.Store(documentID)
	api.waitProcessing(admin, documentID, "ready")
	scanned := api.upload(admin, "chat-scanned.pdf", fixtures.PDF(t, fixtures.Page{JPEG: fixtures.JPEG(t, "Chat evidence amount 73 euros")}), `{"title":"Chat evidence scanned PDF"}`, true, 202)
	scannedID := scanned["id"].(string)
	scannedDocumentID.Store(scannedID)
	api.waitProcessing(admin, scannedID, "ready")
	prompt := fmt.Sprintf(`{"requestId":%q,"content":"Read Chat evidence and report its amount."}`, uuid.NewString())
	accepted := api.request(admin, "POST", path+"/messages", prompt, 202, "ChatAcceptedTurn")
	turnID := accepted["assistantMessage"].(map[string]any)["turnId"].(string)
	repeated := api.request(admin, "POST", path+"/messages", prompt, 202, "ChatAcceptedTurn")
	if repeated["assistantMessage"].(map[string]any)["turnId"] != turnID {
		t.Fatal("send retry duplicated")
	}
	api.request(admin, "POST", path+"/messages", strings.Replace(prompt, "Read Chat evidence and report its amount.", "Changed prompt", 1), 409, "Error")
	message := api.waitChat(admin, path, turnID, "completed", "")
	if !strings.Contains(message["content"].(string), "42") || !strings.Contains(message["content"].(string), "73") || len(message["sources"].([]any)) != 2 {
		t.Fatal("tool result/source missing", message)
	}
	sourceIDs := map[string]bool{}
	for _, source := range message["sources"].([]any) {
		sourceIDs[source.(map[string]any)["documentId"].(string)] = true
	}
	if !sourceIDs[documentID] || !sourceIDs[scannedID] {
		t.Fatal("unverified PDF sources", sourceIDs)
	}
	first := api.request(admin, "GET", path+"/messages?limit=1", "", 200, "ChatMessagePage")
	cursor := first["nextCursor"].(string)
	older := api.request(admin, "GET", path+"/messages?limit=1&cursor="+cursor, "", 200, "ChatMessagePage")
	if older["items"].([]any)[0].(map[string]any)["role"] != "user" {
		t.Fatal("message continuation")
	}
	api.request(admin, "GET", path+"/messages?cursor=bad", "", 400, "Error")
	for index := 0; index < 25; index++ {
		api.request(admin, "POST", "/api/v1/documents", fmt.Sprintf(`{"title":"BudgetEvidence%d"}`, index), 201, "Document")
	}
	stress := api.request(admin, "POST", path+"/messages", fmt.Sprintf(`{"requestId":%q,"content":"Deterministic thirty-call budget stress: compare both PDF amounts after exercising all thirty tool calls."}`, uuid.NewString()), 202, "ChatAcceptedTurn")["assistantMessage"].(map[string]any)
	stressID := stress["turnId"].(string)
	stressMessage := api.waitChat(admin, path, stressID, "completed", "")
	if budgetProviderCalls.Load() != 31 || len(stressMessage["sources"].([]any)) != 27 {
		t.Fatal("thirty-call budget did not permit final answer", budgetProviderCalls.Load(), stressMessage)
	}
	stressConnection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	var persistedCalls, catalogCalls, catalogSources int
	err = stressConnection.QueryRow(t.Context(), `SELECT count(*),count(*) FILTER(WHERE kind='list_tools'),(SELECT count(*) FROM chat_sources s JOIN chat_tool_results r ON r.turn_id=s.turn_id AND r.ordinal=s.ordinal WHERE r.turn_id=$1 AND r.kind='list_tools') FROM chat_tool_results WHERE turn_id=$1`, stressID).Scan(&persistedCalls, &catalogCalls, &catalogSources)
	if err != nil || persistedCalls != 30 || catalogCalls != 2 || catalogSources != 0 {
		t.Fatal("persisted budget or catalog sources", persistedCalls, catalogCalls, catalogSources, err)
	}
	guardConversation := api.request(admin, "POST", "/api/v1/chat/conversations", fmt.Sprintf(`{"requestId":%q}`, uuid.NewString()), 201, "ChatConversation")
	guardPath := "/api/v1/chat/conversations/" + guardConversation["id"].(string)
	guardTurn := api.request(admin, "POST", guardPath+"/messages", fmt.Sprintf(`{"requestId":%q,"content":"Deterministic guarded retrieval"}`, uuid.NewString()), 202, "ChatAcceptedTurn")["assistantMessage"].(map[string]any)["turnId"].(string)
	guardMessage := api.waitChat(admin, guardPath, guardTurn, "completed", "")
	if !strings.Contains(guardMessage["content"].(string), "could not reliably verify") {
		t.Fatal("provider ignored stop without a safe fallback", guardMessage)
	}
	var outcomes []string
	if err := stressConnection.QueryRow(t.Context(), "SELECT array_agg(outcome_code ORDER BY ordinal) FROM chat_tool_results WHERE turn_id=$1", guardTurn).Scan(&outcomes); err != nil || strings.Join(outcomes, ",") != "progress,progress,repeated_call,unknown_document,invalid_offset" {
		t.Fatal("tool guard outcomes", outcomes, err)
	}
	_ = stressConnection.Close(context.Background())
	stop()
	base, stop = startServer(t, binary, databaseURL, env)
	api.baseURL = base
	retained := api.request(admin, "GET", settingsPath, "", 200, "ChatConfiguration")
	if retained["revision"] != settings["revision"] || retained["hasApiKey"] != true {
		t.Fatal("settings restart lost credential")
	}
	api.waitChat(admin, path, turnID, "completed", "")
	externalHold.Store(true)
	held := api.request(admin, "POST", path+"/messages", fmt.Sprintf(`{"requestId":%q,"content":"Wait for cancellation."}`, uuid.NewString()), 202, "ChatAcceptedTurn")["assistantMessage"].(map[string]any)
	select {
	case <-externalStarted:
	case <-time.After(20 * time.Second):
		t.Fatal("external turn did not start")
	}
	heldID := held["turnId"].(string)
	cancelled := api.request(admin, "POST", path+"/turns/"+heldID+"/cancel", "", 200, "ChatMessage")
	if cancelled["status"] != "cancelled" {
		t.Fatal("cancel did not fence publication")
	}
	api.waitChat(admin, path, heldID, "cancelled", "")
	deleting := api.request(admin, "POST", "/api/v1/chat/conversations", fmt.Sprintf(`{"requestId":%q}`, uuid.NewString()), 201, "ChatConversation")
	deletingPath := "/api/v1/chat/conversations/" + deleting["id"].(string)
	api.request(admin, "POST", deletingPath+"/messages", fmt.Sprintf(`{"requestId":%q,"content":"Delete this conversation during inference."}`, uuid.NewString()), 202, "ChatAcceptedTurn")
	select {
	case <-externalStarted:
	case <-time.After(20 * time.Second):
		t.Fatal("turn selected for deletion did not start")
	}
	api.request(admin, "DELETE", deletingPath, "", 204, "")
	api.request(admin, "GET", deletingPath, "", 404, "Error")
	api.request(admin, "GET", deletingPath+"/messages", "", 404, "Error")
	externalHold.Store(false)
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	backlog := func(pending bool) {
		state, stage := "ready", "complete"
		if pending {
			state, stage = "processing", "extracting"
		}
		if _, err := connection.Exec(t.Context(), "UPDATE document_processing SET state=$2,stage=$3 WHERE document_id=$1", documentID, state, stage); err != nil {
			t.Fatal(err)
		}
	}
	backlog(true)
	callsBefore := externalCalls.Load()
	admitted := api.request(admin, "POST", path+"/messages", fmt.Sprintf(`{"requestId":%q,"content":"External resource test: run during ingestion."}`, uuid.NewString()), 202, "ChatAcceptedTurn")["assistantMessage"].(map[string]any)
	api.waitChat(admin, path, admitted["turnId"].(string), "completed", "")
	if externalCalls.Load() != callsBefore+1 {
		t.Fatal("external inference was postponed or restarted by ingestion")
	}
	backlog(false)
	externalHold.Store(true)
	running := api.request(admin, "POST", path+"/messages", fmt.Sprintf(`{"requestId":%q,"content":"External resource test: retain active inference."}`, uuid.NewString()), 202, "ChatAcceptedTurn")["assistantMessage"].(map[string]any)
	runningID := running["turnId"].(string)
	select {
	case <-externalStarted:
	case <-time.After(20 * time.Second):
		t.Fatal("external resource turn did not start")
	}
	backlog(true)
	select {
	case <-externalContentionCancelled:
		t.Fatal("ingestion cancelled admitted external inference")
	case <-time.After(1500 * time.Millisecond):
	}
	api.waitChat(admin, path, runningID, "running", "generating")
	externalHold.Store(false)
	api.waitChat(admin, path, runningID, "completed", "")
	backlog(false)
	update("ollama", "qwen3.5:4b", "", "")
	models := api.request(admin, "GET", "/api/v1/system/chat/models?limit=1", "", 200, "ChatModelPage")
	if len(models["items"].([]any)) != 1 || models["nextOffset"] != float64(1) {
		t.Fatal("model pagination", models)
	}
	internalHold.Store(true)
	pending := api.request(admin, "POST", path+"/messages", fmt.Sprintf(`{"requestId":%q,"content":"Test shared Ollama resource."}`, uuid.NewString()), 202, "ChatAcceptedTurn")["assistantMessage"].(map[string]any)
	pendingID := pending["turnId"].(string)
	select {
	case <-internalStarted:
	case <-time.After(20 * time.Second):
		t.Fatal("internal turn did not start")
	}
	backlog(true)
	select {
	case <-internalCancelled:
		t.Fatal("ingestion cancelled admitted internal inference")
	case <-time.After(1500 * time.Millisecond):
	}
	api.waitChat(admin, path, pendingID, "running", "generating")
	stop()
	internalHold.Store(false)
	backlog(false)
	base, stop = startServer(t, binary, databaseURL, env)
	api.baseURL = base
	api.waitChat(admin, path, pendingID, "completed", "")
	api.request(admin, "DELETE", path, "", 204, "")
	api.request(admin, "GET", path, "", 404, "Error")
}

func (api *ingestionAPI) waitChat(token, path, turnID, status, stage string) map[string]any {
	api.t.Helper()
	deadline := time.Now().Add(4 * time.Minute)
	var message map[string]any
	for time.Now().Before(deadline) {
		page := api.request(token, "GET", path+"/messages?limit=50", "", 200, "ChatMessagePage")
		for _, item := range page["items"].([]any) {
			v := item.(map[string]any)
			if v["role"] == "assistant" && v["turnId"] == turnID {
				message = v
				if v["status"] == status && (stage == "" || v["stage"] == stage) {
					return v
				}
				if v["status"] == "failed" || v["status"] == "cancelled" {
					api.t.Fatalf("chat stopped before %s/%s: %v", status, stage, v)
				}
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	api.t.Fatalf("chat did not reach %s/%s: %v", status, stage, message)
	return nil
}
