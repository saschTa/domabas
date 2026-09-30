package routing_test

import (
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
)

func TestNestedGroupsPreserveMiddlewareAndWildcardValues(t *testing.T) {
	var trace []string
	middleware := func(name string) routing.HTTPMiddleware {
		return func(next http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				trace = append(trace, name+" in")
				next.ServeHTTP(w, r)
				trace = append(trace, name+" out")
			})
		}
	}
	groups := []routing.HTTPRouteGroup{{
		Prefix: "/", Middleware: []routing.HTTPMiddleware{middleware("root"), middleware("second")},
		Children: []routing.HTTPRouteGroup{{
			Prefix: "/api/v1/documents", Middleware: []routing.HTTPMiddleware{middleware("document")},
			Children: []routing.HTTPRouteGroup{{
				Prefix: "/{id}", Middleware: []routing.HTTPMiddleware{middleware("item")},
				Children: []routing.HTTPRouteGroup{{Prefix: "/ocr", Middleware: []routing.HTTPMiddleware{middleware("ocr")}}},
			}},
		}, {
			Prefix: "/api/v1/users", Middleware: []routing.HTTPMiddleware{middleware("users")},
		}},
	}}
	router := routing.NewHTTPRouter(groups...)
	groups[0].Prefix = "/changed"
	groups[0].Middleware[0] = middleware("changed")
	groups[0].Children[0].Prefix = "/changed"
	groups[0].Children[0].Middleware[0] = middleware("changed")
	groups[0].Children[0].Children[0].Children[0].Middleware[0] = middleware("changed")
	for _, path := range []string{
		"/api/v1/documents", "/api/v1/documents/{id}", "/api/v1/documents/{id}/ocr",
		"/api/v1/documents-archive", "/api/v1/users", "/healthz",
	} {
		router.HandleFunc("GET "+path, func(w http.ResponseWriter, r *http.Request) {
			trace = append(trace, "handler")
			w.Header().Set("Document-ID", r.PathValue("id"))
			w.WriteHeader(http.StatusNoContent)
		})
	}
	for _, test := range []struct {
		path  string
		chain []string
		id    string
	}{
		{"/api/v1/documents", []string{"root", "second", "document"}, ""},
		{"/api/v1/documents/abc", []string{"root", "second", "document", "item"}, "abc"},
		{"/api/v1/documents/a%2Fb/ocr", []string{"root", "second", "document", "item", "ocr"}, "a/b"},
		{"/api/v1/documents-archive", []string{"root", "second"}, ""},
		{"/api/v1/users", []string{"root", "second", "users"}, ""},
		{"/healthz", []string{"root", "second"}, ""},
	} {
		t.Run(test.path, func(t *testing.T) {
			trace = nil
			response := httptest.NewRecorder()
			router.ServeHTTP(response, httptest.NewRequest(http.MethodGet, test.path, nil))
			var want []string
			for _, name := range test.chain {
				want = append(want, name+" in")
			}
			want = append(want, "handler")
			for index := len(test.chain) - 1; index >= 0; index-- {
				want = append(want, test.chain[index]+" out")
			}
			if !slices.Equal(trace, want) || response.Code != http.StatusNoContent || response.Header().Get("Document-ID") != test.id {
				t.Fatalf("response %d, id %q, trace %v; want id %q, trace %v", response.Code, response.Header().Get("Document-ID"), trace, test.id, want)
			}
		})
	}
}

func TestServeMuxMethodAndPathBehavior(t *testing.T) {
	calls := 0
	router := routing.NewHTTPRouter(routing.HTTPRouteGroup{Prefix: "/documents"})
	router.HandleFunc("GET /documents/{id}", func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.PathValue("id") != "abc" {
			t.Fatalf("wildcard = %q", r.PathValue("id"))
		}
		w.WriteHeader(http.StatusNoContent)
	})
	for _, test := range []struct {
		method string
		path   string
		status int
		allow  string
	}{
		{http.MethodGet, "/documents/abc", 204, ""},
		{http.MethodHead, "/documents/abc", 204, ""},
		{http.MethodPost, "/documents/abc", 405, "GET, HEAD"},
		{http.MethodGet, "/documents/abc/extra", 404, ""},
		{http.MethodGet, "/documents//abc", 307, ""},
	} {
		response := httptest.NewRecorder()
		router.ServeHTTP(response, httptest.NewRequest(test.method, test.path, nil))
		if response.Code != test.status || response.Header().Get("Allow") != test.allow {
			t.Fatalf("%s %s: status %d, Allow %q", test.method, test.path, response.Code, response.Header().Get("Allow"))
		}
	}
	if calls != 2 {
		t.Fatalf("handler calls = %d; want 2", calls)
	}
}

func TestInvalidGroupConfigurationFailsAtConstruction(t *testing.T) {
	for _, test := range []struct {
		name   string
		groups []routing.HTTPRouteGroup
	}{
		{"relative prefix", []routing.HTTPRouteGroup{{Prefix: "documents"}}},
		{"trailing slash", []routing.HTTPRouteGroup{{Prefix: "/documents/"}}},
		{"nested root", []routing.HTTPRouteGroup{{Prefix: "/documents", Children: []routing.HTTPRouteGroup{{Prefix: "/"}}}}},
		{"duplicate", []routing.HTTPRouteGroup{{Prefix: "/documents"}, {Prefix: "/documents"}}},
		{"unrelated overlap", []routing.HTTPRouteGroup{{Prefix: "/documents"}, {Prefix: "/documents/{id}"}}},
		{"reverse overlap", []routing.HTTPRouteGroup{{Prefix: "/documents/{id}"}, {Prefix: "/documents"}}},
	} {
		t.Run(test.name, func(t *testing.T) {
			defer func() {
				if recover() == nil {
					t.Fatal("invalid route groups accepted")
				}
			}()
			routing.NewHTTPRouter(test.groups...)
		})
	}
}
