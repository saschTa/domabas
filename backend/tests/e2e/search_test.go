//go:build e2e

package e2e_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/jackc/pgx/v5"
)

func TestSearchAndBrowseCursorStrictHTTPNamespaceAndRevocation(t *testing.T) {
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
	defer stop()
	api := &ingestionAPI{t: t, baseURL: baseURL, client: &http.Client{Timeout: 15 * time.Second}, spec: spec}
	register := func(email string) map[string]any {
		return api.request("", "POST", "/api/v1/auth/register", fmt.Sprintf(`{"accountName":"Search acceptance","email":%q,"password":"Search acceptance password 2026!"}`, email), 201, "AuthSession")
	}
	owner := register("search-owner@example.test")
	token := owner["token"].(string)
	identity := owner["identity"].(map[string]any)
	account := identity["account"].(map[string]any)["id"].(string)
	user := identity["user"].(map[string]any)["id"].(string)
	foreign := register("search-foreign@example.test")["token"].(string)
	for i := range 3 {
		doc := api.request(token, "POST", "/api/v1/documents", fmt.Sprintf(`{"title":"Invoice %d"}`, i), 201, "Document")
		kind := []string{"document", "letter", "email"}[i]
		api.request(token, "PATCH", "/api/v1/documents/"+doc["id"].(string), fmt.Sprintf(`{"kind":%q,"tags":["İ","ΟΣ"],"sender":"A%%_Sender","bcc":["B%%_Recipient"]}`, kind), 200, "Document")
	}
	body := func(cursor string) string {
		value := map[string]any{"mode": "fulltext", "query": "", "tags": []string{"İ", "ΟΣ"}, "sender": "%_sENDER", "recipient": "%_rECIPIENT", "sort": "title", "limit": 1}
		if cursor != "" {
			value["cursor"] = cursor
		}
		encoded, _ := json.Marshal(value)
		return string(encoded)
	}
	first := api.request(token, "POST", "/api/v1/documents/search", body(""), 200, "DocumentSearchResults")
	if first["total"] != float64(3) {
		t.Fatalf("Unicode/literal filters: %v", first)
	}
	cursor := first["nextCursor"].(string)
	second := api.request(token, "POST", "/api/v1/documents/search", body(cursor), 200, "DocumentSearchResults")
	if second["total"] != float64(3) || second["items"].([]any)[0].(map[string]any)["document"].(map[string]any)["title"] != "Invoice 1" {
		t.Fatalf("cursor page: %v", second)
	}
	api.request(foreign, "POST", "/api/v1/documents/search", body(cursor), 400, "Error")
	list := api.request(token, "GET", "/api/v1/documents?limit=1", "", 200, "DocumentList")
	listCursor := list["nextCursor"].(string)
	listPath := "/api/v1/documents?limit=1&cursor=" + url.QueryEscape(listCursor)
	api.request(token, "GET", listPath, "", 200, "DocumentList")
	api.request(foreign, "GET", listPath, "", 400, "Error")
	api.request(token, "POST", "/api/v1/documents/search", body(listCursor), 400, "Error")
	emails := api.request(token, "POST", "/api/v1/documents/search", `{"query":"","mode":"hybrid","kinds":["email"]}`, 200, "DocumentSearchResults")
	if emails["total"] != float64(1) || emails["items"].([]any)[0].(map[string]any)["document"].(map[string]any)["kind"] != "email" {
		t.Fatalf("email filter: %v", emails)
	}
	nonEmails := api.request(token, "POST", "/api/v1/documents/search", `{"query":"Invoice","mode":"fulltext","kinds":["document","letter"],"limit":1,"sort":"title"}`, 200, "DocumentSearchResults")
	if nonEmails["total"] != float64(2) {
		t.Fatalf("exclude emails: %v", nonEmails)
	}
	nonEmailCursor := nonEmails["nextCursor"].(string)
	next := api.request(token, "POST", "/api/v1/documents/search", fmt.Sprintf(`{"query":"Invoice","mode":"fulltext","kinds":["letter","document"],"limit":1,"sort":"title","cursor":%q}`, nonEmailCursor), 200, "DocumentSearchResults")
	if next["total"] != float64(2) || next["items"].([]any)[0].(map[string]any)["document"].(map[string]any)["kind"] != "letter" {
		t.Fatalf("non-email page: %v", next)
	}
	api.request(token, "POST", "/api/v1/documents/search", fmt.Sprintf(`{"query":"Invoice","mode":"fulltext","kinds":["email"],"limit":1,"sort":"title","cursor":%q}`, nonEmailCursor), 400, "Error")
	for _, kinds := range []string{`null`, `["unknown"]`, `[null]`, `"email"`} {
		api.request(token, "POST", "/api/v1/documents/search", `{"query":"","mode":"fulltext","kinds":`+kinds+`}`, 400, "Error")
	}
	for _, path := range []string{"/api/v1/documents?cursor=", "/api/v1/documents?limit=1&cursor=" + url.QueryEscape(listCursor) + "&offset=1", "/api/v1/documents?limit=2&cursor=" + url.QueryEscape(listCursor)} {
		api.request(token, "GET", path, "", 400, "Error")
	}
	for _, invalid := range []string{`{"query":"","mode":"fulltext","cursor":""}`, `{"query":"","mode":"fulltext","sender":null}`, `{"query":"","mode":"fulltext","recipient":1}`, `{"query":"","mode":"fulltext","sort":"title","sort":"newest"}`, `{"query":"\ud800","mode":"fulltext"}`, `{"query":"","mode":"fulltext","tags":["İ","i"]}`} {
		api.request(token, "POST", "/api/v1/documents/search", invalid, 400, "Error")
	}
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	if _, err = connection.Exec(t.Context(), `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, account, user); err != nil {
		t.Fatal(err)
	}
	api.request(token, "GET", listPath, "", 401, "Error")
	api.request(token, "POST", "/api/v1/documents/search", body(cursor), 401, "Error")
}
