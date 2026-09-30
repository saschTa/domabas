package models

import (
	"net/http"
	"testing"
	"time"
)

func TestPersistentBrowserCookieBoundsAndFlags(t *testing.T) {
	now := time.Date(2026, 9, 18, 12, 0, 0, 0, time.UTC)
	if BrowserCookie(t.Context(), "token", nil) != nil {
		t.Fatal("native response received cookie")
	}
	for _, secure := range []bool{false, true} {
		ctx := WithSessionRequest(t.Context(), IdentitySessionRequest{Browser: true, Secure: secure, Now: now})
		cookie := BrowserCookie(ctx, "token", nil)
		if cookie.MaxAge != 400*24*60*60 || !cookie.HttpOnly || cookie.Secure != secure || cookie.SameSite != http.SameSiteStrictMode || cookie.Domain != "" || cookie.Path != "/" {
			t.Fatalf("persistent cookie %+v", cookie)
		}
		expiry := now.Add(time.Hour)
		finite := BrowserCookie(ctx, "token", &expiry)
		if finite.MaxAge != 3600 || !finite.Expires.Equal(expiry) {
			t.Fatalf("finite expiry extended %+v", finite)
		}
		cleared := BrowserCookie(ctx, "", nil)
		if cleared.Name != cookie.Name || cleared.MaxAge != -1 || cleared.Value != "" || !cleared.Expires.Before(now) {
			t.Fatalf("clear cookie %+v", cleared)
		}
	}
}
