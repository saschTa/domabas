package routes

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestChatModelContextQueryHasIsolatedParameters(t *testing.T) {
	for _, test := range []struct {
		path   string
		status int
	}{
		{"/api/v1/system/chat/model-context?model=library%2Fqwen3.5%3A4b", 204},
		{"/api/v1/system/chat/model-context?model=a&model=b", 400},
		{"/api/v1/system/chat/model-context?model=", 400},
		{"/api/v1/system/chat/model-context?model=a&limit=20", 400},
		{"/api/v1/system/chat/models?model=a", 400},
		{"/api/v1/system/chat/models?limit=20&offset=0", 204},
	} {
		t.Run(test.path, func(t *testing.T) {
			response := httptest.NewRecorder()
			chatQuery(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(204) })).ServeHTTP(response, httptest.NewRequest(http.MethodGet, test.path, nil))
			if response.Code != test.status {
				t.Fatal(response.Code, response.Body.String())
			}
		})
	}
}
