package transport

import (
	"context"
	"errors"
	"net/http"
	"strings"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type HTTPAuthenticator interface {
	Authenticate(context.Context, string) (domain.IdentityPrincipal, error)
}
type HTTPAuthorizer interface {
	Allows(domain.IdentityPrincipal, domain.IdentityPermission) bool
}
type httpPrincipalKey struct{}
type HTTPIdentityGuard struct {
	authenticator HTTPAuthenticator
	authorizer    HTTPAuthorizer
}

func NewHTTPIdentityGuard(authenticator HTTPAuthenticator, authorizer HTTPAuthorizer) *HTTPIdentityGuard {
	if authenticator == nil || authorizer == nil {
		panic("security dependencies are required")
	}
	return &HTTPIdentityGuard{authenticator: authenticator, authorizer: authorizer}
}
func Principal(ctx context.Context) (domain.IdentityPrincipal, bool) {
	p, ok := ctx.Value(httpPrincipalKey{}).(domain.IdentityPrincipal)
	return p, ok
}
func (g *HTTPIdentityGuard) Require(permission domain.IdentityPermission) func(http.Handler) http.Handler {
	return g.require(permission, false)
}
func (g *HTTPIdentityGuard) RequireAll(permissions ...domain.IdentityPermission) func(http.Handler) http.Handler {
	return g.require("", true, permissions...)
}
func (g *HTTPIdentityGuard) RequireCompleteSession() func(http.Handler) http.Handler {
	return g.require("", true)
}
func (g *HTTPIdentityGuard) require(permission domain.IdentityPermission, normal bool, additional ...domain.IdentityPermission) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Cache-Control", "no-store")
			values := r.Header.Values("Authorization")
			if len(values) != 1 {
				WriteError(w, 401, "unauthorized", "a valid session is required")
				return
			}
			parts := strings.Split(values[0], " ")
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || parts[1] == "" {
				WriteError(w, 401, "unauthorized", "a valid session is required")
				return
			}
			p, err := g.authenticator.Authenticate(r.Context(), parts[1])
			if err != nil {
				if !errors.Is(err, domain.ErrUnauthorized) {
					WriteError(w, 500, "internal_error", "an unexpected error occurred")
					return
				}
				WriteError(w, 401, "unauthorized", "a valid session is required")
				return
			}
			if permission != "" || normal {
				if p.MustChangePassword {
					WriteError(w, 403, "password_change_required", "change your password before continuing")
					return
				}
				if permission != "" && !g.authorizer.Allows(p, permission) {
					WriteError(w, 403, "forbidden", "permission denied")
					return
				}
				for _, claim := range additional {
					if claim == "" || !g.authorizer.Allows(p, claim) {
						WriteError(w, 403, "forbidden", "permission denied")
						return
					}
				}
			}
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), httpPrincipalKey{}, p)))
		})
	}
}

func (g *HTTPIdentityGuard) ByPatternAll(permissions map[string][]domain.IdentityPermission) func(http.Handler) http.Handler {
	copied := make(map[string][]domain.IdentityPermission, len(permissions))
	for pattern, claims := range permissions {
		copied[pattern] = append([]domain.IdentityPermission{}, claims...)
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims := copied[r.Pattern]
			if len(claims) == 0 {
				WriteError(w, http.StatusForbidden, "forbidden", "permission denied")
				return
			}
			g.RequireAll(claims...)(next).ServeHTTP(w, r)
		})
	}
}
func (g *HTTPIdentityGuard) ByMethod(permissions map[string]domain.IdentityPermission) func(http.Handler) http.Handler {
	copy := make(map[string]domain.IdentityPermission, len(permissions))
	for method, permission := range permissions {
		copy[method] = permission
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			permission, ok := copy[r.Method]
			if !ok || permission == "" {
				w.Header().Set("Cache-Control", "no-store")
				WriteError(w, 403, "forbidden", "permission denied")
				return
			}
			g.Require(permission)(next).ServeHTTP(w, r)
		})
	}
}

func (g *HTTPIdentityGuard) ByPattern(permissions map[string]domain.IdentityPermission) func(http.Handler) http.Handler {
	copy := make(map[string]domain.IdentityPermission, len(permissions))
	for pattern, permission := range permissions {
		copy[pattern] = permission
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			permission, ok := copy[r.Pattern]
			if !ok || permission == "" {
				WriteError(w, http.StatusForbidden, "forbidden", "permission denied")
				return
			}
			g.Require(permission)(next).ServeHTTP(w, r)
		})
	}
}

func (g *HTTPIdentityGuard) RequireAny(permissions ...domain.IdentityPermission) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return g.RequireCompleteSession()(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			principal, ok := Principal(r.Context())
			if ok {
				for _, permission := range permissions {
					if permission != "" && g.authorizer.Allows(principal, permission) {
						next.ServeHTTP(w, r)
						return
					}
				}
			}
			WriteError(w, 403, "forbidden", "permission denied")
		}))
	}
}
