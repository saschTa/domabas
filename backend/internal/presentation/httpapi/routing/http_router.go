package routing

import (
	"context"
	"net/http"
	"strings"
	"time"
)

type HTTPMiddleware func(http.Handler) http.Handler

type HTTPRouter struct {
	mux    *http.ServeMux
	scopes []httpRouteScope
}

func NewHTTPRouter(groups ...HTTPRouteGroup) *HTTPRouter {
	router := &HTTPRouter{mux: http.NewServeMux()}
	for _, group := range groups {
		router.addGroup("", nil, 10*time.Second, false, group)
	}
	return router
}

func (router *HTTPRouter) addGroup(parent string, inherited []HTTPMiddleware, timeout time.Duration, streaming bool, group HTTPRouteGroup) {
	if !strings.HasPrefix(group.Prefix, "/") || (group.Prefix != "/" && strings.HasSuffix(group.Prefix, "/")) || (parent != "" && group.Prefix == "/") {
		panic("route group prefix must start with / and have no trailing slash")
	}
	prefix := strings.TrimSuffix(parent, "/") + group.Prefix
	for _, existing := range router.scopes {
		if existing.prefix == prefix {
			panic("duplicate route group prefix: " + prefix)
		}
		overlaps := within(prefix, existing.prefix) || within(existing.prefix, prefix)
		ancestor := parent != "" && within(parent, existing.prefix)
		if overlaps && !ancestor {
			panic("overlapping route groups must be declared as children: " + prefix)
		}
	}
	middleware := append(append([]HTTPMiddleware(nil), inherited...), group.Middleware...)
	if group.Streaming && group.Timeout != 0 {
		panic("streaming routes cannot override timeout")
	}
	streaming = streaming || group.Streaming
	if group.Timeout != 0 {
		if streaming {
			panic("streaming routes cannot override timeout")
		}
		if group.Timeout < 0 {
			panic("route timeout must be positive")
		}
		timeout = group.Timeout
	}
	router.scopes = append(router.scopes, httpRouteScope{prefix: prefix, middleware: middleware, timeout: timeout, streaming: streaming})
	for _, child := range group.Children {
		router.addGroup(prefix, middleware, timeout, streaming, child)
	}
}

func (router *HTTPRouter) HandleFunc(pattern string, handler func(http.ResponseWriter, *http.Request)) {
	_, path, hasMethod := strings.Cut(pattern, " ")
	if !hasMethod {
		path = pattern
	}
	selected := httpRouteScope{timeout: 10 * time.Second}
	for _, candidate := range router.scopes {
		if within(path, candidate.prefix) && len(candidate.prefix) > len(selected.prefix) {
			selected = candidate
		}
	}
	var wrapped http.Handler = http.HandlerFunc(handler)
	for index := len(selected.middleware) - 1; index >= 0; index-- {
		wrapped = selected.middleware[index](wrapped)
	}
	router.mux.Handle(pattern, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if selected.streaming {
			wrapped.ServeHTTP(w, r)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), selected.timeout)
		defer cancel()
		wrapped.ServeHTTP(w, r.WithContext(ctx))
	}))
}

func within(path, prefix string) bool {
	return prefix == "/" || path == prefix || strings.HasPrefix(path, prefix+"/")
}

func (router *HTTPRouter) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	router.mux.ServeHTTP(w, r)
}
