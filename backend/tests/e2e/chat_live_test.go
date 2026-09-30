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

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestAIChatLivePDFDiscoveryAndEvidence(t *testing.T) {
	if os.Getenv("LLM_OLLAMA_URL") == "" {
		t.Fatal("LLM_OLLAMA_URL is required for live PDF chat validation")
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
	token := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Live PDF chat","email":"live-chat@example.test","password":"Live PDF chat password 2026!"}`, 201, "AuthSession")["token"].(string)
	settings := api.request(token, "GET", "/api/v1/system/chat/configuration", "", 200, "ChatConfiguration")
	api.request(token, "PUT", "/api/v1/system/chat/configuration", fmt.Sprintf(`{"expectedRevision":%v,"enabled":true,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"","clearApiKey":true}`, settings["revision"]), 200, "ChatConfiguration")
	first := api.upload(token, "northwind.pdf", fixtures.PDF(t, fixtures.Page{Text: "Northwind electricity bill. Amount due: 42 euros."}), `{"title":"Chat evidence Northwind electricity bill"}`, true, 202)["id"].(string)
	second := api.upload(token, "contoso.pdf", fixtures.PDF(t, fixtures.Page{Text: "Contoso water bill. Amount due: 17 euros."}), `{"title":"Chat evidence Contoso water bill"}`, true, 202)["id"].(string)
	api.waitProcessing(token, first, "ready")
	api.waitProcessing(token, second, "ready")
	conversation := api.request(token, "POST", "/api/v1/chat/conversations", fmt.Sprintf(`{"requestId":%q}`, uuid.NewString()), 201, "ChatConversation")["id"].(string)
	path := "/api/v1/chat/conversations/" + conversation
	accepted := api.request(token, "POST", path+"/messages", fmt.Sprintf(`{"requestId":%q,"content":"First use list_tools to learn about the available tools. Search for Chat evidence, then read both the Northwind electricity bill and Contoso water bill. What amount is due on each bill, and what is their combined amount in euros? Use the PDF text and do not guess."}`, uuid.NewString()), 202, "ChatAcceptedTurn")
	turn := accepted["assistantMessage"].(map[string]any)["turnId"].(string)
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	defer func() {
		rows, err := connection.Query(t.Context(), "SELECT ordinal,kind,text_offset,query FROM chat_tool_results WHERE turn_id=$1 ORDER BY ordinal", turn)
		if err != nil {
			t.Logf("Tool progression unavailable: %v", err)
			return
		}
		defer rows.Close()
		for rows.Next() {
			var ordinal, offset int
			var kind, query string
			if err := rows.Scan(&ordinal, &kind, &offset, &query); err != nil {
				t.Error(err)
				return
			}
			t.Logf("Live PDF tool %d: %s offset %d query %q", ordinal+1, kind, offset, query)
		}
	}()
	message := api.waitChat(token, path, turn, "completed", "")
	answer := message["content"].(string)
	t.Logf("Live PDF answer: %s", answer)
	for _, amount := range []string{"42", "17", "59"} {
		if !strings.Contains(answer, amount) {
			t.Errorf("Live PDF answer omitted expected amount %s", amount)
		}
	}
	consulted := make(map[string]bool)
	for _, source := range message["sources"].([]any) {
		consulted[source.(map[string]any)["documentId"].(string)] = true
	}
	if len(consulted) != 2 || !consulted[first] || !consulted[second] {
		t.Errorf("Live PDF answer must retain both trusted source IDs")
	}
	var calls, catalogs, reads int
	if err := connection.QueryRow(t.Context(), "SELECT count(*),count(*) FILTER(WHERE kind='list_tools'),count(DISTINCT document_id) FILTER(WHERE kind='read_document') FROM chat_tool_results WHERE turn_id=$1", turn).Scan(&calls, &catalogs, &reads); err != nil {
		t.Fatal(err)
	}
	if calls > 30 || catalogs == 0 || reads != 2 {
		t.Fatalf("Live model did not discover and read both PDFs: calls=%d catalogs=%d documentsRead=%d", calls, catalogs, reads)
	}
}
