package routes

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/presentation/identity/models"
)

func TestBrowserSessionOriginAndCredentialBoundaries(t *testing.T) {
	for _, test := range []struct {
		name, origin, marker, cookie, authorization string
		status                                      int
		browser                                     bool
	}{
		{name: "native", status: 204},
		{name: "native bearer", authorization: "Bearer native-token", status: 204},
		{name: "cookie ignored without marker", cookie: "domabas_session=ignored", status: 204},
		{name: "same origin", origin: "http://127.0.0.1:8080", marker: "1", cookie: "domabas_session=token", status: 204, browser: true},
		{name: "allowed cross port", origin: "http://127.0.0.1:7357", marker: "1", status: 204, browser: true},
		{name: "missing origin", marker: "1", status: 403},
		{name: "null origin", origin: "null", marker: "1", status: 403},
		{name: "untrusted origin", origin: "https://evil.example", marker: "1", status: 403},
		{name: "untrusted port", origin: "http://127.0.0.1:9000", marker: "1", status: 403},
		{name: "path is not origin", origin: "http://127.0.0.1:8080/", marker: "1", status: 403},
		{name: "invalid marker", origin: "http://127.0.0.1:8080", marker: "true", status: 403},
		{name: "mixed credentials", origin: "http://127.0.0.1:8080", marker: "1", cookie: "domabas_session=token", authorization: "Bearer other", status: 401},
		{name: "duplicate cookies", origin: "http://127.0.0.1:8080", marker: "1", cookie: "domabas_session=a; domabas_session=b", status: 401},
		{name: "malformed named cookie", origin: "http://127.0.0.1:8080", marker: "1", cookie: "domabas_session=\"unterminated", status: 401},
		{name: "malformed duplicate cookie", origin: "http://127.0.0.1:8080", marker: "1", cookie: "domabas_session=a; domabas_session=\"unterminated", status: 401},
	} {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:8080/api/v1/auth/restore", nil)
			request.Pattern = "POST /api/v1/auth/restore"
			for name, value := range map[string]string{"Origin": test.origin, "X-Domabas-Browser": test.marker, "Cookie": test.cookie, "Authorization": test.authorization} {
				if value != "" {
					request.Header.Set(name, value)
				}
			}
			response := httptest.NewRecorder()
			called := false
			handler := browserSessions([]string{"http://127.0.0.1:7357"}, time.Now)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				called = true
				state := models.CurrentSessionRequest(r.Context())
				if state.Browser != test.browser || (!state.Browser && test.authorization == "" && state.Token != "") {
					t.Fatalf("credential boundary %+v", state)
				}
				w.WriteHeader(204)
			}))
			handler.ServeHTTP(response, request)
			if response.Code != test.status || called != (test.status == 204) {
				t.Fatalf("status %d called %v", response.Code, called)
			}
			if test.status == 401 && response.Result().Cookies()[0].MaxAge != -1 {
				t.Fatal("ambiguous cookie was not cleared")
			}
		})
	}
}

func TestBrowserCookieMutationsRejectUntrustedOriginsBeforeDelegation(t *testing.T) {
	for _, pattern := range []string{"POST /api/v1/auth/register", "POST /api/v1/auth/login", "POST /api/v1/auth/switch-account", "DELETE /api/v1/auth/session", "PUT /api/v1/auth/password"} {
		request := httptest.NewRequest(http.MethodPost, "https://app.example/api/v1/auth/login", nil)
		request.Pattern = pattern
		request.Header.Set("X-Domabas-Browser", "1")
		request.Header.Set("Origin", "https://evil.example")
		response := httptest.NewRecorder()
		browserSessions(nil, time.Now)(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { t.Fatal("untrusted request reached auth handler") })).ServeHTTP(response, request)
		if response.Code != 403 || len(response.Result().Cookies()) != 0 {
			t.Fatalf("unsafe mutation: %d %v", response.Code, response.Header())
		}
	}
}

func TestBrowserLogoutClearsPersistenceBeforeBearerRejection(t *testing.T) {
	request := httptest.NewRequest(http.MethodDelete, "https://app.example/api/v1/auth/session", nil)
	request.Pattern = "DELETE /api/v1/auth/session"
	request.Header.Set("X-Domabas-Browser", "1")
	request.Header.Set("Origin", "https://app.example")
	response := httptest.NewRecorder()
	browserSessions(nil, time.Now)(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(401) })).ServeHTTP(response, request)
	cookies := response.Result().Cookies()
	if response.Code != 401 || len(cookies) != 1 || cookies[0].Name != models.SecureBrowserSessionCookieName || cookies[0].MaxAge != -1 || !cookies[0].Secure || !cookies[0].HttpOnly {
		t.Fatalf("logout cookie: %v", cookies)
	}
}

func TestBrowserOriginRejectsMalformedAndDuplicateOrigins(t *testing.T) {
	for _, origin := range []string{"http://user@app.example", "https://user@app.example", "https://app.example?query", "https://app.example#fragment", "https://app.example?", "https://app.example#", "ftp://app.example"} {
		request := httptest.NewRequest("POST", "http://app.example/", nil)
		request.Header.Set("Origin", origin)
		if _, ok := trustedBrowserOrigin(request, []string{origin}); ok {
			t.Fatalf("accepted unsafe origin %q", origin)
		}
	}
	request := httptest.NewRequest("POST", "https://app.example/", nil)
	request.Header.Add("Origin", "https://app.example")
	request.Header.Add("Origin", "https://app.example")
	if _, ok := trustedBrowserOrigin(request, nil); ok {
		t.Fatal("accepted duplicate origins")
	}
}

func TestBrowserSessionsSupportHTTPHostsAndHTTPSProxies(t *testing.T) {
	for _, test := range []struct {
		name, authority, origin string
		allowed                 []string
		secure, forbidden       bool
	}{
		{name: "LAN IP", authority: "192.168.0.230", origin: "http://192.168.0.230"},
		{name: "LAN port", authority: "192.168.0.230:8088", origin: "http://192.168.0.230:8088"},
		{name: "LAN IPv6", authority: "[fd00::230]:8088", origin: "http://[fd00::230]:8088"},
		{name: "hostname", authority: "documents.example:8088", origin: "http://documents.example:8088"},
		{name: "allowed origin", authority: "192.168.0.230:8080", origin: "http://192.168.0.230:8088", allowed: []string{"http://192.168.0.230:8088"}},
		{name: "untrusted origin", authority: "192.168.0.230", origin: "http://evil.example", forbidden: true},
		{name: "untrusted port", authority: "192.168.0.230:8088", origin: "http://192.168.0.230:9000", forbidden: true},
		{name: "HTTPS proxy", authority: "documents.example", origin: "https://documents.example", secure: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			cookieName := models.BrowserSessionCookieName
			if test.secure {
				cookieName = models.SecureBrowserSessionCookieName
			}
			request := httptest.NewRequest(http.MethodPost, "http://"+test.authority+"/api/v1/auth/restore", nil)
			request.Pattern = "POST /api/v1/auth/restore"
			request.Header.Set("X-Domabas-Browser", "1")
			request.Header.Set("Origin", test.origin)
			request.Header.Set("Cookie", cookieName+"=session-token")
			response := httptest.NewRecorder()
			called := false
			browserSessions(test.allowed, time.Now)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				called = true
				state := models.CurrentSessionRequest(r.Context())
				if !state.Browser || !state.HasCredential || state.Secure != test.secure || state.Token != "session-token" {
					t.Fatalf("session request: %+v", state)
				}
				http.SetCookie(w, models.BrowserCookie(r.Context(), state.Token, nil))
				w.WriteHeader(http.StatusNoContent)
			})).ServeHTTP(response, request)
			cookies := response.Result().Cookies()
			if test.forbidden {
				if response.Code != http.StatusForbidden || called || len(cookies) != 0 {
					t.Fatalf("untrusted origin accepted: %d, called %v, cookies %v", response.Code, called, cookies)
				}
				return
			}
			if response.Code != http.StatusNoContent || !called || len(cookies) != 1 {
				t.Fatalf("session restore: %d, called %v, cookies %v", response.Code, called, cookies)
			}
			cookie := cookies[0]
			if cookie.Name != cookieName || cookie.Value != "session-token" || cookie.Secure != test.secure || !cookie.HttpOnly || cookie.SameSite != http.SameSiteStrictMode || cookie.Path != "/" || cookie.Domain != "" || cookie.MaxAge <= 0 {
				t.Fatalf("session cookie: %+v", cookie)
			}
		})
	}
}
