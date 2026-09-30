//go:build e2e && llm_live

package e2e_test

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestAIChatLiveExampleDocuments(t *testing.T) {
	if os.Getenv("LLM_OLLAMA_URL") == "" {
		t.Fatal("LLM_OLLAMA_URL is required for live example document validation")
	}
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
	base, stop := startServer(t, binary, databaseURL, env)
	defer stop()
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 15 * time.Second}, spec: spec}
	token := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Live chat examples","email":"chat-examples@example.test","password":"Live chat examples password 2026!"}`, 201, "AuthSession")["token"].(string)
	settings := api.request(token, "GET", "/api/v1/system/chat/configuration", "", 200, "ChatConfiguration")
	api.request(token, "PUT", "/api/v1/system/chat/configuration", fmt.Sprintf(`{"expectedRevision":%v,"enabled":true,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"","clearApiKey":true}`, settings["revision"]), 200, "ChatConfiguration")
	older := api.upload(token, "arbeitsvertrag-2024.pdf", fixtures.PDF(t,
		fixtures.Page{Text: "Arbeitsvertrag ab 01.01.2024. Arbeitgeber: Beispiel GmbH."},
		fixtures.Page{Text: "Monatliches Gehalt: 4200 EUR brutto."},
	), `{"title":"Arbeitsvertrag Beispiel GmbH 2024"}`, true, 202)["id"].(string)
	latest := api.upload(token, "arbeitsvertrag-2026.pdf", fixtures.PDF(t,
		fixtures.Page{Text: "Arbeitsvertrag ab 01.01.2026. Arbeitgeber: Beispiel GmbH."},
		fixtures.Page{Text: "Monatliches Gehalt: 4800 EUR brutto."},
		fixtures.Page{Text: "Dieser Vertrag ersetzt den Arbeitsvertrag vom 01.01.2024."},
	), `{"title":"Arbeitsvertrag Beispiel GmbH 2026"}`, true, 202)["id"].(string)
	api.waitProcessing(token, older, "ready")
	api.waitProcessing(token, latest, "ready")
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	for _, example := range []struct {
		name, prompt string
	}{
		{"greeting", "hi"},
		{"latest_salary", "was ist mein letztes gehalt nach arbeitsvertrag?"},
		{"missing_document", "Wie hoch ist der Betrag meiner Einhornversicherung-Rechnung?"},
	} {
		t.Run(example.name, func(t *testing.T) {
			api := &ingestionAPI{t: t, baseURL: base, client: api.client, spec: spec}
			conversation := api.request(token, "POST", "/api/v1/chat/conversations", fmt.Sprintf(`{"requestId":%q}`, uuid.NewString()), 201, "ChatConversation")["id"].(string)
			path := "/api/v1/chat/conversations/" + conversation
			accepted := api.request(token, "POST", path+"/messages", fmt.Sprintf(`{"requestId":%q,"content":%q}`, uuid.NewString(), example.prompt), 202, "ChatAcceptedTurn")
			turn := accepted["assistantMessage"].(map[string]any)["turnId"].(string)
			t.Cleanup(func() { api.request(token, "DELETE", path, "", 204, "") })
			defer inspectLiveChatExampleTools(t, connection, turn, example.name, latest)
			message := api.waitChat(token, path, turn, "completed", "")
			answer := message["content"].(string)
			t.Logf("Prompt: %s\nAnswer: %s", example.prompt, answer)
			if strings.TrimSpace(answer) == "" {
				t.Error("live chat returned an empty answer")
			}
			if example.name == "latest_salary" {
				normalized := strings.NewReplacer(".", "", ",", "", " ", "", "\u00a0", "", "\u202f", "").Replace(answer)
				if !strings.Contains(normalized, "4800") {
					t.Error("answer omitted the latest contract salary of 4800 EUR")
				}
				found := false
				for _, source := range message["sources"].([]any) {
					found = found || source.(map[string]any)["documentId"] == latest
				}
				if !found {
					t.Error("answer omitted the latest contract source")
				}
			}
		})
	}
}

func inspectLiveChatExampleTools(t *testing.T, connection *pgx.Conn, turn, example, latest string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	rows, err := connection.Query(ctx, "SELECT ordinal,kind,query,COALESCE(document_id::text,''),text_offset,result_text,outcome_code FROM chat_tool_results WHERE turn_id=$1 ORDER BY ordinal", turn)
	if err != nil {
		t.Error(err)
		return
	}
	defer rows.Close()
	type chatExampleToolCallKey struct {
		kind, query, document string
		offset                int
	}
	seen := make(map[chatExampleToolCallKey]bool)
	calls, repeats, rejected := 0, 0, 0
	readLatest := false
	for rows.Next() {
		var ordinal int
		var call chatExampleToolCallKey
		var result, outcome string
		if err := rows.Scan(&ordinal, &call.kind, &call.query, &call.document, &call.offset, &result, &outcome); err != nil {
			t.Error(err)
			return
		}
		calls++
		if (m.ChatToolResult{Outcome: outcome}).Executed() {
			call.query = m.ChatSearchQueryKey(call.query)
			if seen[call] {
				repeats++
			}
			seen[call] = true
			readLatest = readLatest || (call.kind == "read_document" && call.document == latest && call.offset == 0)
		} else {
			rejected++
		}
		t.Logf("Tool %d: %s query=%q document=%s offset=%d outcome=%s result=%s", ordinal+1, call.kind, call.query, call.document, call.offset, outcome, result)
	}
	if err := rows.Err(); err != nil {
		t.Error(err)
	}
	t.Logf("Tool summary: attempts=%d rejected=%d repeatedExecutions=%d", calls, rejected, repeats)
	if repeats != 0 {
		t.Errorf("executed %d identical tool calls again", repeats)
	}
	if calls > 30 {
		t.Errorf("tool budget exceeded: %d", calls)
	}
	if example == "greeting" && calls != 0 {
		t.Error("a greeting should not require document tools or discovery")
	}
	if example == "latest_salary" && !readLatest {
		t.Error("model did not read the latest contract")
	}
	if example == "missing_document" && calls == 0 {
		t.Error("model did not search for the requested missing document")
	}
}
