package models

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

const BrowserSessionCookieName = "domabas_session"
const SecureBrowserSessionCookieName = "__Host-domabas_session"

func BrowserCookie(ctx context.Context, token string, expiry *time.Time) *http.Cookie {
	request := CurrentSessionRequest(ctx)
	if !request.Browser {
		return nil
	}
	name := BrowserSessionCookieName
	if request.Secure {
		name = SecureBrowserSessionCookieName
	}
	cookie := &http.Cookie{Name: name, Value: token, Path: "/", HttpOnly: true, Secure: request.Secure, SameSite: http.SameSiteStrictMode}
	if token == "" {
		cookie.MaxAge = -1
		cookie.Expires = time.Unix(1, 0).UTC()
		return cookie
	}
	lifetime := 400 * 24 * time.Hour
	if expiry != nil && expiry.Sub(request.Now) < lifetime {
		lifetime = expiry.Sub(request.Now)
	}
	cookie.MaxAge = max(1, int(lifetime.Seconds()))
	cookie.Expires = request.Now.Add(lifetime).UTC()
	return cookie
}

type IdentitySessionResponse struct {
	body   contract.AuthSession
	status int
	cookie *http.Cookie
}

func NewIdentitySessionResponse(ctx context.Context, session contract.AuthSession, status int) IdentitySessionResponse {
	return IdentitySessionResponse{body: session, status: status, cookie: BrowserCookie(ctx, session.Token, session.ExpiresAt)}
}

func (r IdentitySessionResponse) write(w http.ResponseWriter) error {
	if r.cookie != nil {
		http.SetCookie(w, r.cookie)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(r.status)
	return json.NewEncoder(w).Encode(r.body)
}

func (r IdentitySessionResponse) VisitRegisterResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentitySessionResponse) VisitLoginResponse(w http.ResponseWriter) error { return r.write(w) }
func (r IdentitySessionResponse) VisitSwitchAccountResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentitySessionResponse) VisitRestoreSessionResponse(w http.ResponseWriter) error {
	return r.write(w)
}

type IdentityPasswordChangedResponse struct{ Cookie *http.Cookie }

func (r IdentityPasswordChangedResponse) VisitChangePasswordResponse(w http.ResponseWriter) error {
	if r.Cookie != nil {
		http.SetCookie(w, r.Cookie)
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}
