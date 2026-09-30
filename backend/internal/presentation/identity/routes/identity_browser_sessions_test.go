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

func TestBrowserOriginRejectsExternalPlaintextAndDuplicateOrigins(t *testing.T) {
	for _, origin := range []string{"http://app.example", "http://192.168.0.100", "https://user@app.example", "https://app.example?query", "https://app.example#fragment", "https://app.example?", "https://app.example#"} {
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
