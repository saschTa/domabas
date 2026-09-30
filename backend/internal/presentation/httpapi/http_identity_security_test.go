package httpapi

import (
	"context"
	"io"
	"log/slog"
	"net/http/httptest"
	"strings"
	"testing"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

type deniedAuthenticator struct{ calls int }

func (a *deniedAuthenticator) Authenticate(context.Context, string) (domain.IdentityPrincipal, error) {
	a.calls++
	return domain.IdentityPrincipal{}, domain.ErrUnauthorized
}

type denyAuthorizer struct{}

func (denyAuthorizer) Allows(domain.IdentityPrincipal, domain.IdentityPermission) bool { return false }
func TestEveryProtectedIdentityOperationAuthenticatesBeforeDecoding(t *testing.T) {
	auth := &deniedAuthenticator{}
	router := NewHTTPRouter(NewHTTPHandler(nil, nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(auth, denyAuthorizer{}), nil, slog.New(slog.NewTextHandler(io.Discard, nil)))
	for _, test := range []struct{ method, path string }{{"GET", "/api/v1/auth/session"}, {"HEAD", "/api/v1/auth/session"}, {"DELETE", "/api/v1/auth/session"}, {"PUT", "/api/v1/auth/password"}, {"GET", "/api/v1/account/users?limit=oops"}, {"HEAD", "/api/v1/account/users"}, {"POST", "/api/v1/account/users"}, {"PATCH", "/api/v1/account/users/not-a-uuid"}, {"GET", "/api/v1/documents?limit=oops"}, {"HEAD", "/api/v1/documents"}, {"GET", "/api/v1/documents/not-a-uuid"}, {"POST", "/api/v1/documents"}} {
		t.Run(test.method+test.path, func(t *testing.T) {
			request := httptest.NewRequest(test.method, test.path, strings.NewReader("{malformed"))
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			if response.Code != 401 || response.Header().Get("Cache-Control") != "no-store" {
				t.Fatalf("status=%d headers=%v body=%s", response.Code, response.Header(), response.Body.String())
			}
		})
	}
	if auth.calls != 0 {
		t.Fatal("missing token should be rejected before authenticator")
	}
	for _, path := range []string{"/api/v1/auth/register", "/api/v1/auth/login"} {
		request := httptest.NewRequest("POST", path, strings.NewReader("{malformed"))
		request.Header.Set("Content-Type", "application/json")
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		if response.Code != 400 || response.Header().Get("Cache-Control") != "no-store" {
			t.Fatalf("public endpoint=%s status=%d", path, response.Code)
		}
	}
}

type restrictedAuthenticator struct{}

func (restrictedAuthenticator) Authenticate(context.Context, string) (domain.IdentityPrincipal, error) {
	return domain.IdentityPrincipal{MustChangePassword: true}, nil
}
func TestNewIdentityRoutesRejectInitialPasswordBeforeDecoding(t *testing.T) {
	router := NewHTTPRouter(NewHTTPHandler(nil, nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(restrictedAuthenticator{}, denyAuthorizer{}), nil, slog.New(slog.NewTextHandler(io.Discard, nil)))
	for _, test := range []struct{ method, path string }{{"GET", "/api/v1/auth/accounts?limit=wrong"}, {"GET", "/api/v1/auth/claims"}, {"POST", "/api/v1/auth/switch-account"}, {"POST", "/api/v1/auth/accept-invitation"}, {"POST", "/api/v1/account/invitations"}, {"DELETE", "/api/v1/account/invitations/bad"}, {"GET", "/api/v1/system/users?limit=wrong"}, {"PATCH", "/api/v1/system/users/bad"}} {
		r := httptest.NewRequest(test.method, test.path, strings.NewReader("{bad"))
		r.Header.Set("Authorization", "Bearer token")
		w := httptest.NewRecorder()
		router.ServeHTTP(w, r)
		if w.Code != 403 || !strings.Contains(w.Body.String(), "password_change_required") {
			t.Fatalf("%s %s: %d %s", test.method, test.path, w.Code, w.Body.String())
		}
	}
}
