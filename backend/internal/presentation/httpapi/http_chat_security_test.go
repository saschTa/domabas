package httpapi

import (
	"io"
	"log/slog"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

func TestChatRoutesAuthenticateBeforeDecoding(t *testing.T) {
	router := NewHTTPRouter(NewHTTPHandler(nil, nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(&deniedAuthenticator{}, denyAuthorizer{}), nil, slog.New(slog.NewTextHandler(io.Discard, nil)))
	for _, test := range []struct{ method, path string }{
		{"GET", "/api/v1/chat/configuration"}, {"GET", "/api/v1/chat/conversations?limit=nope"}, {"POST", "/api/v1/chat/conversations"}, {"GET", "/api/v1/chat/conversations/not-an-id"}, {"DELETE", "/api/v1/chat/conversations/not-an-id"}, {"GET", "/api/v1/chat/conversations/not-an-id/messages"}, {"POST", "/api/v1/chat/conversations/not-an-id/messages"}, {"POST", "/api/v1/chat/conversations/not-an-id/turns/not-an-id/cancel"}, {"GET", "/api/v1/system/chat/configuration"}, {"PUT", "/api/v1/system/chat/configuration"}, {"GET", "/api/v1/system/chat/models?offset=oops"},
	} {
		t.Run(test.method+test.path, func(t *testing.T) {
			w := httptest.NewRecorder()
			r := httptest.NewRequest(test.method, test.path, strings.NewReader("{bad"))
			router.ServeHTTP(w, r)
			if w.Code != 401 {
				t.Fatalf("status %d: %s", w.Code, w.Body)
			}
		})
	}
}
