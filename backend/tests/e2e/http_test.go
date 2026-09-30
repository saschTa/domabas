//go:build e2e

package e2e_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"

	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
)

func TestAuthenticatedLibrariesAndPermissionsPersistAcrossRestart(t *testing.T) {
	if os.Getenv("TEMPORAL_ADDRESS") == "" || os.Getenv("TEMPORAL_NAMESPACE") == "" {
		t.Fatal("TEMPORAL_ADDRESS and TEMPORAL_NAMESPACE are required for API E2E tests")
	}
	databaseURL := testdb.New(t)
	serverEnvironment := newServerEnvironment(t, databaseURL)
	name := "server"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	binary := filepath.Join(t.TempDir(), name)
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build server: %v\n%s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(t.Context()); err != nil {
		t.Fatalf("invalid OpenAPI contract: %v", err)
	}
	baseURL, stop := startServer(t, binary, databaseURL, serverEnvironment)
	client := &http.Client{Timeout: 10 * time.Second}
	request := func(token, method, path, body string, status int, schema string, extra ...http.Header) map[string]any {
		t.Helper()
		req, err := http.NewRequest(method, baseURL+path, strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		for _, headers := range extra {
			for key, values := range headers {
				for _, value := range values {
					req.Header.Add(key, value)
				}
			}
		}
		response, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		data, err := io.ReadAll(response.Body)
		if err != nil {
			t.Fatal(err)
		}
		if response.StatusCode != status {
			t.Fatalf("%s %s: status %d, expected %d: %s", method, path, response.StatusCode, status, data)
		}
		if strings.HasPrefix(path, "/api/v1/") && !strings.Contains(response.Header.Get("Cache-Control"), "no-store") {
			t.Fatalf("%s %s: private response permits caching", method, path)
		}
		if schema == "" {
			if len(data) != 0 {
				t.Fatalf("%s %s: expected no response body", method, path)
			}
			return nil
		}
		if !strings.HasPrefix(response.Header.Get("Content-Type"), "application/json") {
			t.Fatalf("non-JSON response: %s", data)
		}
		var decoded map[string]any
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("decode response: %v: %s", err, data)
		}
		if err := spec.Components.Schemas[schema].Value.VisitJSON(decoded); err != nil {
			t.Fatalf("response violates %s schema: %v", schema, err)
		}
		return decoded
	}
	body := func(value any) string {
		t.Helper()
		encoded, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		return string(encoded)
	}
	assertCode := func(response map[string]any, code string) {
		t.Helper()
		if response["code"] != code {
			t.Fatalf("error code %v, expected %s", response["code"], code)
		}
	}
	assertIdentity := func(identity map[string]any, email, role, accountID string, restricted bool, permissions ...string) {
		t.Helper()
		if slices.Contains(permissions, "documents:read") {
			permissions = append(permissions, "documents:download", "documents:thumbnails:read", "documents:search", "documents:ocr:read", "invoices:read")
		}
		if !restricted && (role == "admin" || role == "user") {
			permissions = append(permissions, "documents:upload", "documents:update", "documents:retry", "documents:unlock", "documents:ocr:update", "documents:delete", "email:manage", "paperless:import")
		}
		if !restricted {
			permissions = append(permissions, "activity:read:own", "realtime:connect", "chat:use")
		}
		if !restricted && role == "admin" {
			permissions = append(permissions, "documents:jobs:read", "documents:reindex")
		}
		if slices.Contains(permissions, "system:users:manage") {
			permissions = append(permissions, "system:document-processing:manage", "system:paperless:manage", "system:chat:manage", "system:workloads:manage")
		}
		user := identity["user"].(map[string]any)
		account := identity["account"].(map[string]any)
		if user["email"] != email || user["mustChangePassword"] != restricted || identity["role"] != role || account["id"] != accountID {
			t.Fatalf("unexpected identity: %v", identity)
		}
		actual := make([]string, 0, len(identity["permissions"].([]any)))
		for _, value := range identity["permissions"].([]any) {
			actual = append(actual, value.(string))
		}
		slices.Sort(actual)
		slices.Sort(permissions)
		if !slices.Equal(actual, permissions) {
			t.Fatalf("permissions %v, expected %v", actual, permissions)
		}
	}
	login := func(email, password string, status int) map[string]any {
		t.Helper()
		schema := "AuthSession"
		if status != http.StatusOK {
			schema = "Error"
		}
		return request("", "POST", "/api/v1/auth/login", body(map[string]any{"email": email, "password": password}), status, schema)
	}
	switchAccount := func(token, accountID string) map[string]any {
		t.Helper()
		session := request(token, "POST", "/api/v1/auth/switch-account", body(map[string]any{"accountId": accountID}), 200, "AuthSession")
		if session["token"] == token || session["identity"].(map[string]any)["account"].(map[string]any)["id"] != accountID {
			t.Fatal("namespace switch did not replace the bearer and scope")
		}
		request(token, "GET", "/api/v1/auth/session", "", 401, "Error")
		return session
	}
	request("", "GET", "/healthz", "", 200, "Health")
	request("", "GET", "/readyz", "", 200, "Health")
	protectedRoutes := []struct{ method, path string }{
		{"GET", "/api/v1/documents?limit=invalid"},
		{"GET", "/api/v1/documents/not-a-uuid"},
		{"POST", "/api/v1/documents"},
		{"POST", "/api/v1/documents/upload"},
		{"POST", "/api/v1/documents/search"},
		{"PATCH", "/api/v1/documents/not-a-uuid"},
		{"GET", "/api/v1/documents/not-a-uuid/content"},
		{"GET", "/api/v1/documents/not-a-uuid/thumbnail"},
		{"GET", "/api/v1/documents/not-a-uuid/processing"},
		{"POST", "/api/v1/documents/not-a-uuid/retry"},
		{"GET", "/api/v1/system/document-processing"},
		{"PUT", "/api/v1/system/document-processing"},
		{"GET", "/api/v1/system/workload-settings"},
		{"PUT", "/api/v1/system/workload-settings"},
		{"GET", "/api/v1/auth/session"},
		{"DELETE", "/api/v1/auth/session"},
		{"PUT", "/api/v1/auth/password"},
		{"GET", "/api/v1/account/users?limit=invalid"},
		{"POST", "/api/v1/account/users"},
		{"PATCH", "/api/v1/account/users/not-a-uuid"},
		{"GET", "/api/v1/auth/accounts?limit=invalid"},
		{"GET", "/api/v1/auth/claims"},
		{"POST", "/api/v1/auth/switch-account"},
		{"POST", "/api/v1/auth/accept-invitation"},
		{"GET", "/api/v1/account/invitations?limit=invalid"},
		{"POST", "/api/v1/account/invitations"},
		{"DELETE", "/api/v1/account/invitations/not-a-uuid"},
		{"GET", "/api/v1/system/users?limit=invalid"},
		{"PATCH", "/api/v1/system/users/not-a-uuid"},
	}
	for _, route := range protectedRoutes {
		assertCode(request("", route.method, route.path, "{", 401, "Error"), "unauthorized")
	}
	request("", "HEAD", "/api/v1/documents", "", 401, "")
	for _, invalidToken := range []string{"invalid", strings.Repeat("A", 43), strings.Repeat("a", 44)} {
		assertCode(request(invalidToken, "GET", "/api/v1/auth/session", "", 401, "Error"), "unauthorized")
	}
	for _, invalid := range []string{
		`{}`, `null`, `{"accountName":"A","email":"invalid","password":"A sufficiently long password"}`,
		`{"accountName":"A","email":"a@example.test","password":"short"}`,
		`{"accountName":"A","email":"a@example.test","password":null}`,
		`{"accountName":"A","email":"a@example.test","password":"A sufficiently long password","role":"owner"}`,
		`{"accountName":"A","email":"a@example.test","email":"b@example.test","password":"A sufficiently long password"}`,
		`{"accountName":"A","Email":"a@example.test","password":"A sufficiently long password"}`,
	} {
		request("", "POST", "/api/v1/auth/register", invalid, 400, "Error")
	}
	const passwordA = "Account A password 903!"
	const passwordB = "Account B password 904!"
	emailA, emailB := "owner-a@example.test", "owner-b@example.test"
	registeredA := request("", "POST", "/api/v1/auth/register", body(map[string]any{
		"accountName": "  Account A  ", "email": " OWNER-A@EXAMPLE.TEST ", "password": passwordA,
	}), 201, "AuthSession")
	tokenA := registeredA["token"].(string)
	identityA := registeredA["identity"].(map[string]any)
	accountA := identityA["account"].(map[string]any)["id"].(string)
	ownerA := identityA["user"].(map[string]any)["id"].(string)
	assertIdentity(identityA, emailA, "admin", accountA, false, "documents:read", "documents:create", "users:manage", "system:users:manage")
	if identityA["isOwner"] != true || identityA["systemRole"] != "admin" || len(identityA["claims"].([]any)) != 0 {
		t.Fatalf("first user did not own its library and bootstrap system administration: %v", identityA)
	}
	if identityA["account"].(map[string]any)["name"] != "Account A" {
		t.Fatal("account name was not normalized")
	}
	if registeredA["expiresAt"] != nil {
		t.Fatalf("new session has routine expiry: %v", registeredA["expiresAt"])
	}
	request("", "POST", "/api/v1/auth/register", body(map[string]any{
		"accountName": "Duplicate", "email": "OWNER-A@example.test", "password": passwordA,
	}), 409, "Error")
	unknown := login("missing@example.test", passwordA, 401)
	wrong := login(emailA, "Incorrect account password", 401)
	assertCode(unknown, "invalid_credentials")
	if unknown["code"] != wrong["code"] || unknown["message"] != wrong["message"] {
		t.Fatal("login distinguishes unknown users from wrong passwords")
	}
	assertCode(login(emailA, "x", 401), "invalid_credentials")
	assertIdentity(request(tokenA, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), emailA, "admin", accountA, false, "documents:read", "documents:create", "users:manage", "system:users:manage")
	request(tokenA, "GET", "/api/v1/auth/session", "", 401, "Error", http.Header{"Authorization": {"Bearer " + tokenA}})
	request("", "GET", "/api/v1/documents?access_token="+tokenA, "", 401, "Error")
	request("", "GET", "/api/v1/documents", "", 401, "Error", http.Header{"Cookie": {"token=" + tokenA}})
	empty := request(tokenA, "GET", "/api/v1/documents", "", 200, "DocumentList")
	if len(empty["items"].([]any)) != 0 || empty["total"] != float64(0) {
		t.Fatalf("new schema was not empty: %v", empty)
	}
	for _, body := range []string{
		`{`, `{}`, `null`, `{"title":null}`, `{"title":" "}`,
		`{"title":"Invoice","unknown":true}`, `{"title":"Invoice","description":null}`,
		`{"title":"Invoice"} {"title":"second"}`, `{"title":123}`,
		fmt.Sprintf(`{"title":%q}`, strings.Repeat("界", 201)),
		fmt.Sprintf(`{"title":"Invoice","description":%q}`, strings.Repeat("🙂", 4001)),
	} {
		request(tokenA, "POST", "/api/v1/documents", body, 400, "Error")
	}
	request(tokenA, "POST", "/api/v1/documents", `{"title":"`+strings.Repeat("a", 33*1024)+`"}`, 413, "Error")
	for _, path := range []string{"?limit=0", "?limit=101", "?offset=-1", "?limit=invalid", "/invalid-uuid"} {
		request(tokenA, "GET", "/api/v1/documents"+path, "", 400, "Error")
	}
	request(tokenA, "GET", "/api/v1/documents/00000000-0000-4000-8000-000000000000", "", 404, "Error")
	created := request(tokenA, "POST", "/api/v1/documents", `{"title":"  Tax 2026  ","description":"Private records"}`, 201, "Document")
	if created["title"] != "Tax 2026" {
		t.Fatalf("title not normalized: %v", created)
	}
	id := created["id"].(string)
	request(tokenA, "GET", "/api/v1/documents/"+id, "", 200, "Document")
	request(tokenA, "HEAD", "/api/v1/documents/"+id, "", 200, "")
	request(tokenA, "POST", "/api/v1/documents", `{"title":"Second"}`, 201, "Document")
	page := request(tokenA, "GET", "/api/v1/documents?limit=1&offset=1", "", 200, "DocumentList")
	if page["total"] != float64(2) || page["items"].([]any)[0].(map[string]any)["id"] != id {
		t.Fatalf("pagination failed: %v", page)
	}
	for _, origin := range []string{"http://localhost:7357", "https://unlisted.example"} {
		req, _ := http.NewRequest("OPTIONS", baseURL+"/api/v1/documents", nil)
		req.Header.Set("Origin", origin)
		req.Header.Set("Access-Control-Request-Method", "POST")
		response, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		got := response.Header.Get("Access-Control-Allow-Origin")
		if (origin == "http://localhost:7357" && got != origin) || (origin != "http://localhost:7357" && got != "") {
			t.Fatalf("unexpected CORS origin %q for %q", got, origin)
		}
		if origin == "http://localhost:7357" {
			if !strings.Contains(response.Header.Get("Access-Control-Allow-Headers"), "Authorization") {
				t.Fatal("configured browser origin cannot send authorization")
			}
			for _, method := range []string{"GET", "POST", "PUT", "PATCH", "DELETE"} {
				if !strings.Contains(response.Header.Get("Access-Control-Allow-Methods"), method) {
					t.Fatalf("CORS does not allow %s", method)
				}
			}
		}
	}
	registeredB := request("", "POST", "/api/v1/auth/register", body(map[string]any{
		"accountName": "Account B", "email": emailB, "password": passwordB,
	}), 201, "AuthSession")
	tokenB := registeredB["token"].(string)
	identityB := registeredB["identity"].(map[string]any)
	accountB := identityB["account"].(map[string]any)["id"].(string)
	ownerB := identityB["user"].(map[string]any)["id"].(string)
	assertIdentity(identityB, emailB, "admin", accountB, false, "documents:read", "documents:create", "users:manage")
	if identityB["isOwner"] != true || identityB["systemRole"] != "user" {
		t.Fatal("later registration received the wrong ownership or system role")
	}
	request(tokenB, "GET", "/api/v1/system/users?limit=invalid", "", 403, "Error")
	request(tokenB, "PATCH", "/api/v1/system/users/not-a-uuid", "{", 403, "Error")
	if accountA == accountB || ownerA == ownerB {
		t.Fatal("registration reused an account or user")
	}
	for _, suffix := range []string{"", "?accountId=" + accountA, "?limit=1&offset=1&accountId=" + accountA} {
		other := request(tokenB, "GET", "/api/v1/documents"+suffix, "", 200, "DocumentList", http.Header{"X-Account-ID": {accountA}})
		if other["total"] != float64(0) || len(other["items"].([]any)) != 0 {
			t.Fatalf("second account sees first account records: %v", other)
		}
	}
	request(tokenB, "GET", "/api/v1/documents/"+id, "", 404, "Error")
	request(tokenB, "POST", "/api/v1/documents", body(map[string]any{"title": "Wrong scope", "accountId": accountA}), 400, "Error")
	otherDocument := request(tokenB, "POST", "/api/v1/documents", `{"title":"Account B private"}`, 201, "Document")
	request(tokenA, "GET", "/api/v1/documents/"+otherDocument["id"].(string), "", 404, "Error")
	for token, expected := range map[string]float64{tokenA: 2, tokenB: 1} {
		list := request(token, "GET", "/api/v1/documents", "", 200, "DocumentList")
		if list["total"] != expected || float64(len(list["items"].([]any))) != expected {
			t.Fatalf("account list/count mismatch: %v", list)
		}
	}
	request(tokenA, "PATCH", "/api/v1/account/users/"+ownerB, `{"role":"viewer","enabled":false,"claims":[]}`, 404, "Error")
	for _, update := range []string{`{"role":"viewer","enabled":true,"claims":[]}`, `{"role":"admin","enabled":false,"claims":[]}`, `{"role":"admin","enabled":true,"claims":["documents:read"]}`} {
		assertCode(request(tokenA, "PATCH", "/api/v1/account/users/"+ownerA, update, 409, "Error"), "conflict")
	}
	request(tokenA, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity")
	const viewerEmail = "viewer@example.test"
	const initialPassword = "Initial member password 905!"
	const memberPassword = "Changed member password 906!"
	member := request(tokenA, "POST", "/api/v1/account/users", body(map[string]any{
		"email": viewerEmail, "password": initialPassword, "role": "viewer", "claims": []string{},
	}), 201, "AccountUser")
	memberID := member["id"].(string)
	if member["role"] != "viewer" || member["enabled"] != true || member["mustChangePassword"] != true || member["isOwner"] != false {
		t.Fatalf("unexpected new member: %v", member)
	}
	request(tokenB, "PATCH", "/api/v1/account/users/"+memberID, `{"role":"admin","enabled":true,"claims":[]}`, 404, "Error")
	request(tokenA, "PATCH", "/api/v1/account/users/"+memberID, `{"role":"viewer"}`, 400, "Error")
	request(tokenA, "POST", "/api/v1/account/users", body(map[string]any{
		"email": emailB, "password": initialPassword, "role": "admin", "claims": []string{},
	}), 409, "Error")
	for _, path := range []string{"?limit=0", "?limit=101", "?offset=-1"} {
		request(tokenA, "GET", "/api/v1/account/users"+path, "", 400, "Error")
	}
	members := request(tokenA, "GET", "/api/v1/account/users?limit=1&offset=1", "", 200, "AccountUserList")
	if members["total"] != float64(2) || len(members["items"].([]any)) != 1 {
		t.Fatalf("member pagination failed: %v", members)
	}
	otherMembers := request(tokenB, "GET", "/api/v1/account/users?accountId="+accountA, "", 200, "AccountUserList")
	if otherMembers["total"] != float64(1) || otherMembers["items"].([]any)[0].(map[string]any)["id"] != ownerB {
		t.Fatalf("member list escaped account scope: %v", otherMembers)
	}
	restrictedToken := login(viewerEmail, initialPassword, 200)["token"].(string)
	restrictedIdentity := request(restrictedToken, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity")
	if restrictedIdentity["user"].(map[string]any)["mustChangePassword"] != true {
		t.Fatal("new member did not require password change")
	}
	personalAccount := restrictedIdentity["account"].(map[string]any)["id"].(string)
	if personalAccount == accountA || restrictedIdentity["isOwner"] != true || restrictedIdentity["role"] != "admin" || restrictedIdentity["systemRole"] != "user" {
		t.Fatal("local member did not receive a separate personal namespace")
	}
	for _, route := range protectedRoutes {
		if route.path == "/api/v1/auth/session" || route.path == "/api/v1/auth/password" {
			continue
		}
		assertCode(request(restrictedToken, route.method, route.path, "{", 403, "Error"), "password_change_required")
	}
	assertCode(request(restrictedToken, "PUT", "/api/v1/auth/password", body(map[string]any{
		"currentPassword": "Wrong initial password", "newPassword": memberPassword,
	}), 400, "Error"), "invalid_credentials")
	request(restrictedToken, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity")
	request(restrictedToken, "PUT", "/api/v1/auth/password", body(map[string]any{
		"currentPassword": initialPassword, "newPassword": memberPassword,
	}), 204, "")
	request(restrictedToken, "GET", "/api/v1/auth/session", "", 401, "Error")
	assertCode(login(viewerEmail, initialPassword, 401), "invalid_credentials")
	viewerLogin := login(viewerEmail, memberPassword, 200)
	assertIdentity(viewerLogin["identity"].(map[string]any), viewerEmail, "admin", personalAccount, false, "documents:read", "documents:create", "users:manage")
	viewerSession := switchAccount(viewerLogin["token"].(string), accountA)
	viewerToken := viewerSession["token"].(string)
	if viewerLogin["expiresAt"] != nil || viewerSession["expiresAt"] != nil {
		t.Fatal("namespace switch changed persistent session expiry")
	}
	assertIdentity(request(viewerToken, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), viewerEmail, "viewer", accountA, false, "documents:read")
	request(viewerToken, "GET", "/api/v1/documents/"+id, "", 200, "Document")
	request(viewerToken, "HEAD", "/api/v1/documents/"+id, "", 200, "")
	request(viewerToken, "GET", "/api/v1/documents/"+otherDocument["id"].(string), "", 404, "Error")
	assertCode(request(viewerToken, "POST", "/api/v1/documents", "{", 403, "Error"), "forbidden")
	assertCode(request(viewerToken, "POST", "/api/v1/documents/upload", "{", 403, "Error"), "forbidden")
	assertCode(request(viewerToken, "PATCH", "/api/v1/documents/invalid", "{", 403, "Error"), "forbidden")
	assertCode(request(viewerToken, "POST", "/api/v1/documents/invalid/retry", "{", 403, "Error"), "forbidden")
	request(viewerToken, "POST", "/api/v1/documents/search", `{"query":"Annual","mode":"fulltext"}`, 200, "DocumentSearchResults")
	request(viewerToken, "GET", "/api/v1/documents/"+id+"/content", "", 404, "Error")
	request(viewerToken, "GET", "/api/v1/documents/"+id+"/processing", "", 404, "Error")
	assertCode(request(viewerToken, "POST", "/api/v1/account/users", "{", 403, "Error"), "forbidden")
	assertCode(request(viewerToken, "PATCH", "/api/v1/account/users/invalid", "{", 403, "Error"), "forbidden")
	assertCode(request(viewerToken, "GET", "/api/v1/account/users", "", 403, "Error"), "forbidden")
	request(tokenA, "PATCH", "/api/v1/account/users/"+memberID, `{"role":"user","enabled":true,"claims":[]}`, 200, "AccountUser")
	request(viewerToken, "GET", "/api/v1/documents", "", 401, "Error")
	editorToken := switchAccount(login(viewerEmail, memberPassword, 200)["token"].(string), accountA)["token"].(string)
	assertIdentity(request(editorToken, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), viewerEmail, "user", accountA, false, "documents:read", "documents:create")
	request(editorToken, "POST", "/api/v1/documents", `{"title":"Editor created document"}`, 201, "Document")
	request(editorToken, "GET", "/api/v1/account/users", "", 403, "Error")
	request(tokenA, "PATCH", "/api/v1/account/users/"+memberID, `{"role":"user","enabled":false,"claims":[]}`, 200, "AccountUser")
	request(editorToken, "GET", "/api/v1/auth/session", "", 401, "Error")
	personalToken := login(viewerEmail, memberPassword, 200)["token"].(string)
	assertIdentity(request(personalToken, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), viewerEmail, "admin", personalAccount, false, "documents:read", "documents:create", "users:manage")
	request(personalToken, "POST", "/api/v1/auth/switch-account", body(map[string]any{"accountId": accountA}), 404, "Error")
	request(personalToken, "POST", "/api/v1/auth/switch-account", body(map[string]any{"accountId": accountB}), 404, "Error")
	request(personalToken, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity")
	stop()
	baseURL, stop = startServer(t, binary, databaseURL, serverEnvironment)
	request(tokenA, "GET", "/api/v1/documents/"+id, "", 200, "Document")

	catalog := request(tokenA, "GET", "/api/v1/auth/claims", "", 200, "ClaimList")
	claimScopes := make(map[string]string)
	claimRoles := make(map[string][]string)
	for _, item := range catalog["items"].([]any) {
		claim := item.(map[string]any)
		claimID := claim["id"].(string)
		if _, duplicate := claimScopes[claimID]; duplicate || claim["label"] == "" {
			t.Fatal("claim catalog contains a duplicate or unlabeled claim")
		}
		claimScopes[claimID] = claim["scope"].(string)
		for _, role := range claim["roles"].([]any) {
			claimRoles[claimID] = append(claimRoles[claimID], role.(string))
		}
	}
	for _, claim := range identitymodels.ClaimCatalog() {
		roles := make([]string, len(claim.Roles))
		for index, role := range claim.Roles {
			roles[index] = string(role)
		}
		if !slices.Equal(claimRoles[string(claim.ID)], roles) {
			t.Fatalf("public claim %s does not describe its role bundle", claim.ID)
		}
	}
	for _, claim := range []string{"documents:read", "documents:create", "documents:upload", "documents:update", "documents:download", "documents:thumbnails:read", "documents:search", "documents:retry", "documents:jobs:read", "documents:reindex", "users:manage"} {
		if claimScopes[claim] != "namespace" {
			t.Fatalf("namespace claim %s has scope %q", claim, claimScopes[claim])
		}
	}
	for _, claim := range []string{"system:users:manage", "system:workloads:manage"} {
		if claimScopes[claim] != "system" {
			t.Fatalf("system claim %s was not separately scoped", claim)
		}
	}
	for _, path := range []string{"/api/v1/auth/accounts", "/api/v1/account/invitations", "/api/v1/system/users"} {
		for _, query := range []string{"?limit=0", "?limit=101", "?offset=-1", "?limit=invalid"} {
			request(tokenA, "GET", path+query, "", 400, "Error")
		}
	}
	for _, claims := range []any{nil, []string{"unknown:claim"}, []string{"documents:read", "documents:read"}, []string{"system:users:manage"}, []string{"system:workloads:manage"}, []string{"*"}, []any{1}} {
		request(tokenA, "POST", "/api/v1/account/invitations", body(map[string]any{
			"email": emailB, "role": "viewer", "claims": claims,
		}), 400, "Error")
		request(tokenA, "PATCH", "/api/v1/account/users/"+memberID, body(map[string]any{
			"role": "viewer", "enabled": true, "claims": claims,
		}), 400, "Error")
	}
	request(tokenA, "POST", "/api/v1/account/invitations", body(map[string]any{
		"email": emailB, "role": "viewer", "claims": []string{}, "accountId": accountB,
	}), 400, "Error")
	issueInvitation := func(token, email, role string, claims ...string) map[string]any {
		t.Helper()
		return request(token, "POST", "/api/v1/account/invitations", body(map[string]any{
			"email": email, "role": role, "claims": append([]string{}, claims...),
		}), 201, "IssuedInvitation")
	}
	acceptInvitation := func(token, code string, status int) map[string]any {
		t.Helper()
		schema := "AccountMembership"
		if status != 201 {
			schema = "Error"
		}
		return request(token, "POST", "/api/v1/auth/accept-invitation", body(map[string]any{"code": code}), status, schema)
	}
	unavailable := acceptInvitation(tokenA, strings.Repeat("A", 43), 404)
	assertUnavailable := func(response map[string]any) {
		t.Helper()
		if response["code"] != unavailable["code"] || response["message"] != unavailable["message"] {
			t.Fatalf("invitation failure disclosed its reason: %v", response)
		}
	}
	assertUnavailable(acceptInvitation(tokenA, "not-an-invitation-code", 404))
	issued := issueInvitation(tokenA, " OWNER-B@EXAMPLE.TEST ", "viewer")
	invitation := issued["invitation"].(map[string]any)
	invitationID := invitation["id"].(string)
	code := issued["code"].(string)
	if len(code) != 43 || invitation["email"] != emailB || invitation["status"] != "pending" {
		t.Fatal("invitation code, normalized email or lifecycle state is invalid")
	}
	issuedAt, err := time.Parse(time.RFC3339Nano, invitation["createdAt"].(string))
	if err != nil {
		t.Fatal(err)
	}
	expiresAt, err := time.Parse(time.RFC3339Nano, invitation["expiresAt"].(string))
	if err != nil || expiresAt.Sub(issuedAt) != 7*24*time.Hour {
		t.Fatal("invitation did not receive a fixed seven-day lifetime")
	}
	listedInvitations := request(tokenA, "GET", "/api/v1/account/invitations?limit=1&offset=0", "", 200, "InvitationList")
	if listedInvitations["total"] != float64(1) || len(listedInvitations["items"].([]any)) != 1 || strings.Contains(body(listedInvitations), code) || strings.Contains(body(listedInvitations), "digest") {
		t.Fatal("invitation list pagination failed or leaked the acceptance secret")
	}
	foreignInvitations := request(tokenB, "GET", "/api/v1/account/invitations?accountId="+accountA, "", 200, "InvitationList")
	if foreignInvitations["total"] != float64(0) {
		t.Fatal("invitation list accepted a client-provided namespace")
	}
	request(tokenB, "DELETE", "/api/v1/account/invitations/"+invitationID, "", 404, "Error")
	assertUnavailable(acceptInvitation(tokenA, code, 404))
	request(tokenB, "POST", "/api/v1/auth/accept-invitation", body(map[string]any{"code": code, "accountId": accountB}), 400, "Error")
	accepted := acceptInvitation(tokenB, code, 201)
	if accepted["account"].(map[string]any)["id"] != accountA || accepted["role"] != "viewer" || accepted["isOwner"] != false {
		t.Fatalf("invitation did not preserve its namespace and authority: %v", accepted)
	}
	assertUnavailable(acceptInvitation(tokenB, code, 404))
	assertIdentity(request(tokenB, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), emailB, "admin", accountB, false, "documents:read", "documents:create", "users:manage")
	request(tokenB, "GET", "/api/v1/documents/"+id, "", 404, "Error")
	accounts := request(tokenB, "GET", "/api/v1/auth/accounts?limit=1&offset=1", "", 200, "AccountMembershipList")
	if accounts["total"] != float64(2) || len(accounts["items"].([]any)) != 1 {
		t.Fatal("accepted namespace was not discoverable through paginated memberships")
	}
	sharedB := switchAccount(tokenB, accountA)["token"].(string)
	assertIdentity(request(sharedB, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), emailB, "viewer", accountA, false, "documents:read")
	request(sharedB, "GET", "/api/v1/documents/"+id, "", 200, "Document")
	request(sharedB, "GET", "/api/v1/documents/"+otherDocument["id"].(string), "", 404, "Error")
	request(sharedB, "POST", "/api/v1/documents", "{", 403, "Error")
	request(sharedB, "POST", "/api/v1/account/invitations", "{", 403, "Error")
	request(sharedB, "DELETE", "/api/v1/account/invitations/invalid", "", 403, "Error")
	request(tokenA, "PATCH", "/api/v1/account/users/"+ownerB, `{"role":"viewer","enabled":true,"claims":["documents:create"]}`, 200, "AccountUser")
	request(sharedB, "GET", "/api/v1/auth/session", "", 401, "Error")
	sharedB = switchAccount(login(emailB, passwordB, 200)["token"].(string), accountA)["token"].(string)
	assertIdentity(request(sharedB, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), emailB, "viewer", accountA, false, "documents:read", "documents:create")
	request(sharedB, "POST", "/api/v1/documents", `{"title":"Granted shared write"}`, 201, "Document")
	request(sharedB, "GET", "/api/v1/account/users", "", 403, "Error")
	request(tokenA, "PATCH", "/api/v1/account/users/"+ownerB, `{"role":"viewer","enabled":true,"claims":[]}`, 200, "AccountUser")
	request(sharedB, "GET", "/api/v1/auth/session", "", 401, "Error")
	tokenB = login(emailB, passwordB, 200)["token"].(string)

	request(tokenA, "PATCH", "/api/v1/account/users/"+memberID, `{"role":"viewer","enabled":true,"claims":["users:manage"]}`, 200, "AccountUser")
	delegate := switchAccount(personalToken, accountA)["token"].(string)
	assertIdentity(request(delegate, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), viewerEmail, "viewer", accountA, false, "documents:read", "users:manage")
	request(delegate, "GET", "/api/v1/account/users", "", 200, "AccountUserList")
	request(delegate, "POST", "/api/v1/documents", "{", 403, "Error")
	request(delegate, "PATCH", "/api/v1/account/users/"+ownerA, `{"role":"viewer","enabled":true,"claims":[]}`, 409, "Error")
	for _, update := range []string{`{"role":"user","enabled":true,"claims":[]}`, `{"role":"viewer","enabled":true,"claims":["documents:create"]}`} {
		request(delegate, "PATCH", "/api/v1/account/users/"+ownerB, update, 403, "Error")
	}
	request(delegate, "POST", "/api/v1/account/users", body(map[string]any{
		"email": "escalated@example.test", "password": initialPassword, "role": "user", "claims": []string{},
	}), 403, "Error")
	const invitedEmail = "invited@example.test"
	request(delegate, "POST", "/api/v1/account/invitations", body(map[string]any{"email": invitedEmail, "role": "user", "claims": []string{}}), 403, "Error")
	delegatedInvite := issueInvitation(delegate, invitedEmail, "viewer")
	registeredD := request("", "POST", "/api/v1/auth/register", body(map[string]any{
		"accountName": "Invited personal library", "email": invitedEmail, "password": passwordB,
	}), 201, "AuthSession")
	tokenD := registeredD["token"].(string)
	request(tokenA, "PATCH", "/api/v1/account/users/"+memberID, `{"role":"viewer","enabled":true,"claims":[]}`, 200, "AccountUser")
	request(delegate, "GET", "/api/v1/auth/session", "", 401, "Error")
	assertUnavailable(acceptInvitation(tokenD, delegatedInvite["code"].(string), 404))
	request(tokenA, "DELETE", "/api/v1/account/invitations/"+delegatedInvite["invitation"].(map[string]any)["id"].(string), "", 204, "")
	assertUnavailable(acceptInvitation(tokenD, delegatedInvite["code"].(string), 404))
	request(tokenD, "GET", "/api/v1/documents/"+id, "", 404, "Error")

	const existingEmail = "existing-member@example.test"
	existingInvite := issueInvitation(tokenA, existingEmail, "admin")
	existingMember := request(tokenA, "POST", "/api/v1/account/users", body(map[string]any{
		"email": existingEmail, "password": initialPassword, "role": "viewer", "claims": []string{},
	}), 201, "AccountUser")
	existingToken := login(existingEmail, initialPassword, 200)["token"].(string)
	request(existingToken, "PUT", "/api/v1/auth/password", body(map[string]any{"currentPassword": initialPassword, "newPassword": memberPassword}), 204, "")
	existingToken = login(existingEmail, memberPassword, 200)["token"].(string)
	assertUnavailable(acceptInvitation(existingToken, existingInvite["code"].(string), 404))
	request(tokenA, "PATCH", "/api/v1/account/users/"+existingMember["id"].(string), `{"role":"viewer","enabled":false,"claims":[]}`, 200, "AccountUser")
	assertUnavailable(acceptInvitation(existingToken, existingInvite["code"].(string), 404))
	existingAccounts := request(existingToken, "GET", "/api/v1/auth/accounts", "", 200, "AccountMembershipList")
	if existingAccounts["total"] != float64(1) {
		t.Fatal("invitation reactivated an existing disabled membership")
	}

	bOtherSession := switchAccount(login(emailB, passwordB, 200)["token"].(string), accountA)["token"].(string)
	request(tokenA, "PATCH", "/api/v1/system/users/"+ownerB, `{"role":"admin"}`, 200, "SystemUser")
	request(tokenB, "GET", "/api/v1/auth/session", "", 401, "Error")
	request(bOtherSession, "GET", "/api/v1/auth/session", "", 401, "Error")
	tokenB = login(emailB, passwordB, 200)["token"].(string)
	assertIdentity(request(tokenB, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), emailB, "admin", accountB, false, "documents:read", "documents:create", "users:manage", "system:users:manage")
	users := request(tokenB, "GET", "/api/v1/system/users?limit=1&offset=1", "", 200, "SystemUserList")
	if users["total"] != float64(5) || users["adminCount"] != float64(2) || len(users["items"].([]any)) != 1 {
		t.Fatalf("system user pagination failed: %v", users)
	}
	request(tokenB, "GET", "/api/v1/documents/"+id, "", 404, "Error")
	inviteA := issueInvitation(tokenB, emailA, "viewer")
	acceptInvitation(tokenA, inviteA["code"].(string), 201)
	tokenA = switchAccount(tokenA, accountB)["token"].(string)
	assertIdentity(request(tokenA, "GET", "/api/v1/auth/session", "", 200, "CurrentIdentity"), emailA, "viewer", accountB, false, "documents:read", "system:users:manage")
	request(tokenA, "GET", "/api/v1/documents/"+id, "", 404, "Error")
	request(tokenA, "GET", "/api/v1/documents/"+otherDocument["id"].(string), "", 200, "Document")
	request(tokenA, "POST", "/api/v1/documents", "{", 403, "Error")
	request(tokenA, "GET", "/api/v1/account/users", "", 403, "Error")
	request(tokenA, "GET", "/api/v1/system/users", "", 200, "SystemUserList")
	request(tokenA, "PATCH", "/api/v1/system/users/"+ownerB, `{"role":"user"}`, 200, "SystemUser")
	users = request(tokenA, "GET", "/api/v1/system/users?limit=1", "", 200, "SystemUserList")
	if users["adminCount"] != float64(1) {
		t.Fatal("system administrator count did not update after demotion")
	}
	request(tokenB, "GET", "/api/v1/auth/session", "", 401, "Error")
	request(tokenA, "PATCH", "/api/v1/system/users/"+ownerA, `{"role":"user"}`, 409, "Error")
	request(tokenA, "PATCH", "/api/v1/system/users/"+ownerA, `{"role":"viewer"}`, 400, "Error")
	request(tokenA, "PATCH", "/api/v1/system/users/"+uuid.NewString(), `{"role":"user"}`, 404, "Error")
	tokenA = switchAccount(tokenA, accountA)["token"].(string)
	tokenB = login(emailB, passwordB, 200)["token"].(string)
	request(tokenB, "GET", "/api/v1/system/users?limit=invalid", "", 403, "Error")
	request(tokenB, "PATCH", "/api/v1/system/users/not-a-uuid", "{", 403, "Error")
	crossNamespaceTokenA := switchAccount(login(emailA, passwordA, 200)["token"].(string), accountB)["token"].(string)
	logoutToken := login(emailA, passwordA, 200)["token"].(string)
	request(logoutToken, "DELETE", "/api/v1/auth/session", "", 204, "")
	request(logoutToken, "GET", "/api/v1/documents", "", 401, "Error")
	stop()
	baseURL, stop = startServer(t, binary, databaseURL, serverEnvironment)
	found := request(tokenA, "GET", "/api/v1/documents/"+id, "", 200, "Document")
	if found["description"] != "Private records" {
		t.Fatalf("data did not survive restart: %v", found)
	}
	request(logoutToken, "GET", "/api/v1/auth/session", "", 401, "Error")
	request(editorToken, "GET", "/api/v1/auth/session", "", 401, "Error")
	request(tokenB, "GET", "/api/v1/documents/"+id, "", 404, "Error")
	request(tokenB, "GET", "/api/v1/documents/"+otherDocument["id"].(string), "", 200, "Document")
	request(crossNamespaceTokenA, "GET", "/api/v1/documents/"+otherDocument["id"].(string), "", 200, "Document")
	assertUnavailable(acceptInvitation(tokenB, code, 404))
	retainedInvitations := request(tokenA, "GET", "/api/v1/account/invitations", "", 200, "InvitationList")
	states := make(map[string]string)
	for _, raw := range retainedInvitations["items"].([]any) {
		invitation := raw.(map[string]any)
		states[invitation["id"].(string)] = invitation["status"].(string)
	}
	if states[invitationID] != "accepted" || states[existingInvite["invitation"].(map[string]any)["id"].(string)] != "pending" {
		t.Fatal("invitation lifecycle did not survive restart or a failed acceptance consumed its code")
	}
	secondOwnerToken := login(emailA, passwordA, 200)["token"].(string)
	const changedPassword = "Updated account password 907!"
	request(tokenA, "PUT", "/api/v1/auth/password", body(map[string]any{
		"currentPassword": passwordA, "newPassword": changedPassword,
	}), 204, "")
	request(tokenA, "GET", "/api/v1/auth/session", "", 401, "Error")
	request(secondOwnerToken, "GET", "/api/v1/auth/session", "", 401, "Error")
	request(crossNamespaceTokenA, "GET", "/api/v1/auth/session", "", 401, "Error")
	assertCode(login(emailA, passwordA, 401), "invalid_credentials")
	newToken := login(emailA, changedPassword, 200)["token"].(string)
	request(newToken, "GET", "/api/v1/documents/"+id, "", 200, "Document")
	request(newToken, "DELETE", "/api/v1/auth/session", "", 204, "")
	request(newToken, "GET", "/api/v1/auth/session", "", 401, "Error")
	stop()
	baseURL, _ = startServer(t, binary, databaseURL, serverEnvironment)
	for range 20 {
		assertUnavailable(acceptInvitation(tokenB, strings.Repeat("A", 43), 404))
	}
	assertCode(acceptInvitation(tokenB, strings.Repeat("A", 43), 429), "rate_limited")
}

func newServerEnvironment(t *testing.T, databaseURL string) []string {
	t.Helper()
	if os.Getenv("DOCUMENT_PROCESSOR_URL") == "" {
		t.Fatal("DOCUMENT_PROCESSOR_URL is required for API E2E tests against the real document processor")
	}
	root := t.TempDir()
	queue := "domabas-api-test-" + uuid.NewString()
	t.Cleanup(func() { cleanupOwnedIngestion(t, databaseURL, queue) })
	t.Cleanup(func() { cleanupOwnedPaperless(t, databaseURL, queue) })
	return []string{
		"LLM_CREDENTIAL_KEY=",
		"LLM_CREDENTIAL_KEY_FILE=" + filepath.Join(root, "secrets", "llm.key"),
		"EMAIL_CREDENTIAL_KEYS=",
		"EMAIL_CREDENTIAL_ACTIVE_KEY_ID=",
		"EMAIL_CREDENTIAL_KEY_FILE=" + filepath.Join(root, "secrets", "email.key"),
		"PAPERLESS_CREDENTIAL_KEY=",
		"PAPERLESS_CREDENTIAL_KEY_FILE=" + filepath.Join(root, "secrets", "paperless.key"),
		"DOCUMENT_INGESTION_ROOT=" + filepath.Join(root, "ingestion"),
		"DOCUMENT_STORAGE_ROOT=" + filepath.Join(root, "documents"),
		"TEMPORAL_TASK_QUEUE=" + queue,
	}
}

func startServer(t *testing.T, binary, databaseURL string, environment []string) (string, func()) {
	t.Helper()
	logPath := filepath.Join(t.TempDir(), "server.log")
	log, err := os.Create(logPath)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { log.Close() })
	command := exec.Command(binary)
	for _, variable := range os.Environ() {
		key := strings.SplitN(variable, "=", 2)[0]
		if key != "DATABASE_URL" && key != "HTTP_ADDR" && key != "DOMABAS_ENV_FILE" && key != "CORS_ORIGINS" && key != "TEMPORAL_TASK_QUEUE" && key != "DOCUMENT_INGESTION_ROOT" && key != "DOCUMENT_STORAGE_ROOT" && key != "PAPERLESS_CREDENTIAL_KEY" && key != "PAPERLESS_CREDENTIAL_KEY_FILE" && key != "LLM_CREDENTIAL_KEY" && key != "LLM_CREDENTIAL_KEY_FILE" {
			command.Env = append(command.Env, variable)
		}
	}
	command.Env = append(command.Env, "DATABASE_URL="+databaseURL, "HTTP_ADDR=127.0.0.1:0", "DOMABAS_ENV_FILE=", "CORS_ORIGINS=http://localhost:7357")
	command.Env = append(command.Env, environment...)
	command.Stdout, command.Stderr = log, log
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- command.Wait() }()
	stopped := false
	stop := func() {
		if stopped {
			return
		}
		stopped = true
		if runtime.GOOS == "windows" {
			_ = command.Process.Kill()
		} else {
			_ = command.Process.Signal(syscall.SIGTERM)
		}
		select {
		case err := <-done:
			if err != nil && runtime.GOOS != "windows" {
				t.Errorf("server shutdown: %v", err)
			}
		case <-time.After(45 * time.Second):
			_ = command.Process.Kill()
			<-done
			t.Error("server did not shut down gracefully")
		}
	}
	t.Cleanup(stop)
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		data, _ := os.ReadFile(logPath)
		for line := range bytes.SplitSeq(data, []byte("\n")) {
			var event struct {
				Message string `json:"msg"`
				Address string `json:"address"`
			}
			if json.Unmarshal(line, &event) == nil && event.Message == "server listening" {
				return "http://" + event.Address, stop
			}
		}
		select {
		case err := <-done:
			stopped = true
			t.Fatalf("server exited before startup: %v\n%s", err, data)
		default:
		}
		time.Sleep(25 * time.Millisecond)
	}
	data, _ := os.ReadFile(logPath)
	t.Fatalf("server startup timed out:\n%s", data)
	return "", stop
}
