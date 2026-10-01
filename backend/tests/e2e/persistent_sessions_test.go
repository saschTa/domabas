//go:build e2e

package e2e_test

import (
	"encoding/json"
	"io"
	"net/http"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	identityservices "github.com/domabas/domabas/backend/internal/domain/identity/services"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/jackc/pgx/v5"
)

func TestPersistentBrowserAndNativeSessionLifecycle(t *testing.T) {
	databaseURL := testdb.New(t)
	environment := newServerEnvironment(t, databaseURL)
	name := "persistent-server"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	binary := filepath.Join(t.TempDir(), name)
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build server: %v\n%s", err, output)
	}
	baseURL, stop := startServer(t, binary, databaseURL, environment)
	defer func() { stop() }()
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	api := ingestionAPI{t: t, client: &http.Client{Timeout: 10 * time.Second}, spec: spec}
	request := func(browser bool, token, cookie, method, path, body, origin string, want int, schema string) (map[string]any, []*http.Cookie) {
		t.Helper()
		r, err := http.NewRequest(method, baseURL+path, strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		if browser {
			r.Host = "192.168.0.230:8088"
			r.Header.Set("X-Domabas-Browser", "1")
			if origin == "" {
				origin = "http://" + r.Host
			}
			r.Header.Set("Origin", origin)
		}
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		if cookie != "" {
			r.Header.Set("Cookie", cookie)
		}
		if body != "" {
			r.Header.Set("Content-Type", "application/json")
		}
		response, err := api.client.Do(r)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		data, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
		result := api.decode(response.StatusCode, response.Header, data, err, want, schema)
		return result, response.Cookies()
	}
	cookieValue := func(cookies []*http.Cookie) string {
		t.Helper()
		if len(cookies) != 1 || cookies[0].Name != "domabas_session" || !cookies[0].HttpOnly || cookies[0].Secure || cookies[0].SameSite != http.SameSiteStrictMode || cookies[0].Path != "/" || cookies[0].Domain != "" || cookies[0].MaxAge != 400*24*60*60 {
			t.Fatalf("persistent HTTP cookie: %+v", cookies)
		}
		return cookies[0].Name + "=" + cookies[0].Value
	}
	assertCleared := func(cookies []*http.Cookie) {
		t.Helper()
		if len(cookies) != 1 || cookies[0].MaxAge != -1 || cookies[0].Value != "" || !cookies[0].HttpOnly {
			t.Fatalf("cookie not cleared: %+v", cookies)
		}
	}
	request(true, "", "", "POST", "/api/v1/auth/restore", "", "", 204, "")
	registration := `{"accountName":"Persistent library","email":"persistent@example.test","password":"Q7!m2Rx8"}`
	request(true, "", "", "POST", "/api/v1/auth/register", registration, "https://evil.example", 403, "Error")
	request(true, "", "", "POST", "/api/v1/auth/register", strings.ReplaceAll(registration, "Q7!m2Rx8", "Q7!m2Rx"), "", 400, "Error")
	registered, cookies := request(true, "", "", "POST", "/api/v1/auth/register", registration, "", 201, "AuthSession")
	token := registered["token"].(string)
	cookie := cookieValue(cookies)
	if registered["expiresAt"] != nil {
		t.Fatal("new browser session expires")
	}
	account := registered["identity"].(map[string]any)["account"].(map[string]any)["id"].(string)
	restored, cookies := request(true, "", cookie, "POST", "/api/v1/auth/restore", "", "", 200, "AuthSession")
	if restored["token"] != token || restored["expiresAt"] != nil || cookieValue(cookies) != cookie {
		t.Fatal("restore changed persistent credentials")
	}
	request(false, "", cookie, "GET", "/api/v1/documents", "", "", 401, "Error")
	native, cookies := request(false, token, "", "POST", "/api/v1/auth/restore", "", "", 200, "AuthSession")
	if native["token"] != token || len(cookies) != 0 {
		t.Fatal("native restoration emitted cookie or changed token")
	}
	_, cookies = request(true, token, cookie, "POST", "/api/v1/auth/restore", "", "", 401, "Error")
	assertCleared(cookies)
	loginBody := `{"email":"persistent@example.test","password":"Q7!m2Rx8"}`
	finite, _ := request(false, "", "", "POST", "/api/v1/auth/login", loginBody, "", 200, "AuthSession")
	finiteToken := finite["token"].(string)
	db, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close(t.Context())
	expires := time.Now().UTC().Add(time.Hour).Truncate(time.Microsecond)
	finiteDigest, err := identityservices.TokenDigest(finiteToken)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(t.Context(), "UPDATE sessions SET expires_at=$1 WHERE digest=$2", expires, finiteDigest); err != nil {
		t.Fatal(err)
	}
	finite, cookies = request(true, "", "domabas_session="+finiteToken, "POST", "/api/v1/auth/restore", "", "", 200, "AuthSession")
	parsed, err := time.Parse(time.RFC3339Nano, finite["expiresAt"].(string))
	if err != nil || !parsed.Equal(expires) || len(cookies) != 1 || cookies[0].MaxAge < 3500 || cookies[0].MaxAge > 3600 {
		t.Fatal("retained finite restore changed deadline")
	}
	if _, err := db.Exec(t.Context(), "UPDATE sessions SET expires_at=clock_timestamp()-interval '1 second' WHERE expires_at IS NOT NULL"); err != nil {
		t.Fatal(err)
	}
	_, cookies = request(true, "", "domabas_session="+finiteToken, "POST", "/api/v1/auth/restore", "", "", 401, "Error")
	assertCleared(cookies)
	switchBody, _ := json.Marshal(map[string]string{"accountId": account})
	switched, cookies := request(true, token, cookie, "POST", "/api/v1/auth/switch-account", string(switchBody), "", 200, "AuthSession")
	newToken := switched["token"].(string)
	newCookie := cookieValue(cookies)
	if switched["expiresAt"] != nil || newToken == token {
		t.Fatal("switch failed to replace persistent session")
	}
	request(false, token, "", "POST", "/api/v1/auth/restore", "", "", 401, "Error")
	stop()
	baseURL, stop = startServer(t, binary, databaseURL, environment)
	restored, _ = request(true, "", newCookie, "POST", "/api/v1/auth/restore", "", "", 200, "AuthSession")
	if restored["token"] != newToken {
		t.Fatal("persistent cookie failed after backend restart")
	}
	_, cookies = request(true, newToken, newCookie, "DELETE", "/api/v1/auth/session", "", "", 204, "")
	assertCleared(cookies)
	_, cookies = request(true, "", newCookie, "POST", "/api/v1/auth/restore", "", "", 401, "Error")
	assertCleared(cookies)
	_, cookies = request(true, newToken, newCookie, "DELETE", "/api/v1/auth/session", "", "", 401, "Error")
	assertCleared(cookies)
	loggedIn, cookies := request(true, "", "", "POST", "/api/v1/auth/login", loginBody, "", 200, "AuthSession")
	newToken, newCookie = loggedIn["token"].(string), cookieValue(cookies)
	_, cookies = request(true, newToken, newCookie, "PUT", "/api/v1/auth/password", `{"currentPassword":"Q7!m2Rx8","newPassword":"B8!fresh"}`, "", 204, "")
	assertCleared(cookies)
	request(false, newToken, "", "POST", "/api/v1/auth/restore", "", "", 401, "Error")
}
