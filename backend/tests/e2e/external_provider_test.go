//go:build e2e

package e2e_test

import (
	"fmt"
	"net/http"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/getkin/kin-openapi/openapi3"
)

func TestGenerationRequiresAnExternalEndpoint(t *testing.T) {
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
	defer func() { stop() }()
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 15 * time.Second}, spec: spec}
	admin := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Context library","email":"context-admin@example.test","password":"Context test password 2026!"}`, 201, "AuthSession")["token"].(string)
	chatPath, pipelinePath := "/api/v1/system/chat/configuration", "/api/v1/system/document-processing"
	chat := api.request(admin, "GET", chatPath, "", 200, "ChatConfiguration")
	pipeline := api.request(admin, "GET", pipelinePath, "", 200, "DocumentProcessingConfiguration")
	llm := pipeline["llm"].(map[string]any)
	for _, config := range []map[string]any{chat, llm} {
		if config["enabled"] != false || config["model"] != "" || config["baseUrl"] != "" || config["provider"] != "openai" || config["contextLength"] != nil {
			t.Fatalf("unexpected external provider defaults: %v", config)
		}
	}
	if llm["invoiceEnabled"] != false {
		t.Fatal("invoice AI enabled before configuration")
	}
	for _, value := range []string{
		`"provider":"ollama","model":"local","baseUrl":""`,
		`"provider":"openai","model":"model","baseUrl":""`,
		`"provider":"openai","model":"","baseUrl":"https://provider.test/v1"`,
	} {
		api.request(admin, "PUT", chatPath, fmt.Sprintf(`{"expectedRevision":%.0f,"enabled":true,%s}`, chat["revision"], value), 400, "Error")
		api.request(admin, "PUT", pipelinePath, fmt.Sprintf(`{"expectedRevision":%.0f,"language":%q,"segmentation":%q,"llm":{"enabled":false,"invoiceEnabled":true,%s}}`, pipeline["revision"], pipeline["language"], pipeline["segmentation"], value), 400, "Error")
	}
}
