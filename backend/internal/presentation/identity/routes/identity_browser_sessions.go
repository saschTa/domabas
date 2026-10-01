package routes

import (
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/domabas/domabas/backend/internal/presentation/identity/models"
)

func browserSessions(allowedOrigins []string, now func() time.Time) func(http.Handler) http.Handler {
	origins := slices.Clone(allowedOrigins)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			switch r.Pattern {
			case "POST /api/v1/auth/register", "POST /api/v1/auth/login", "POST /api/v1/auth/switch-account", "POST /api/v1/auth/restore", "DELETE /api/v1/auth/session", "PUT /api/v1/auth/password":
			default:
				next.ServeHTTP(w, r)
				return
			}
			request := models.IdentitySessionRequest{Now: now().UTC()}
			markers := r.Header.Values("X-Domabas-Browser")
			if len(markers) > 0 {
				if len(markers) != 1 || markers[0] != "1" {
					writeError(w, http.StatusForbidden, "forbidden", "browser session request is invalid")
					return
				}
				origin, ok := trustedBrowserOrigin(r, origins)
				if !ok {
					writeError(w, http.StatusForbidden, "forbidden", "browser origin is not permitted")
					return
				}
				request.Browser, request.Secure = true, origin.Scheme == "https"
			}
			if r.Pattern == "POST /api/v1/auth/restore" {
				if request.Browser {
					cookieName := models.BrowserSessionCookieName
					if request.Secure {
						cookieName = models.SecureBrowserSessionCookieName
					}
					cookies := r.CookiesNamed(cookieName)
					occurrences := 0
					for _, header := range r.Header.Values("Cookie") {
						for _, part := range strings.Split(header, ";") {
							name, _, _ := strings.Cut(part, "=")
							if strings.TrimSpace(name) == cookieName {
								occurrences++
							}
						}
					}
					if len(cookies) > 1 || occurrences != len(cookies) || len(r.Header.Values("Authorization")) > 0 {
						http.SetCookie(w, models.BrowserCookie(models.WithSessionRequest(r.Context(), request), "", nil))
						writeError(w, http.StatusUnauthorized, "unauthorized", "session credentials are ambiguous")
						return
					}
					if len(cookies) == 1 {
						request.HasCredential, request.Token = true, cookies[0].Value
					}
				} else {
					values := r.Header.Values("Authorization")
					if len(values) == 1 {
						parts := strings.Split(values[0], " ")
						if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
							request.HasCredential, request.Token = true, parts[1]
						}
					}
				}
			}
			r = r.WithContext(models.WithSessionRequest(r.Context(), request))
			if request.Browser && r.Pattern == "DELETE /api/v1/auth/session" {
				http.SetCookie(w, models.BrowserCookie(r.Context(), "", nil))
			}
			next.ServeHTTP(w, r)
		})
	}
}

func trustedBrowserOrigin(r *http.Request, allowed []string) (*url.URL, bool) {
	values := r.Header.Values("Origin")
	if len(values) != 1 {
		return nil, false
	}
	origin, err := url.Parse(values[0])
	if err != nil || origin.User != nil || origin.Host == "" || values[0] != origin.Scheme+"://"+origin.Host || (origin.Scheme != "http" && origin.Scheme != "https") {
		return nil, false
	}
	if !strings.EqualFold(origin.Host, r.Host) && !slices.Contains(allowed, values[0]) {
		return nil, false
	}
	return origin, true
}
