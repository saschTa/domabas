package routes

import (
	"fmt"
	"testing"
	"time"
)

func TestStrictCredentialModels(t *testing.T) {
	valid := []struct{ operation, body string }{{"login", `{"email":"Alice@Example.test","password":"x"}`}, {"register", `{"accountName":"Home","email":"alice@example.test","password":"a uniquely long password"}`}, {"update_member", `{"role":"viewer","enabled":false,"claims":[]}`}}
	for _, test := range valid {
		if _, err := decodeFields([]byte(test.body), test.operation); err != nil {
			t.Errorf("%s: %v", test.operation, err)
		}
	}
	invalid := []struct{ operation, body string }{{"login", `{"Email":"a@example.test","password":"x"}`}, {"login", `{"email":"a@example.test","password":"x","password":"y"}`}, {"login", `{"email":"a@example.test","password":null}`}, {"login", `{"email":"a@example.test","password":9}`}, {"login", `{"email":"a@example.test","password":"x"} {}`}, {"login", `{"email":"a@example.test","password":"x","extra":true}`}, {"login", `[]`}, {"update_member", `{"role":"viewer"}`}, {"update_member", `{"role":"viewer","enabled":"false"}`}, {"register", `{"accountName":" ","email":"a@example.test","password":"a uniquely long password"}`}, {"register", `{"accountName":"Home","email":"a@example.test","password":"short"}`}}
	for _, test := range invalid {
		if _, err := decodeFields([]byte(test.body), test.operation); err == nil {
			t.Errorf("accepted %s %s", test.operation, test.body)
		}
	}
	if _, err := decodeFields([]byte("{\"email\":\"a@example.test\",\"password\":\"\xff\"}"), "login"); err == nil {
		t.Fatal("invalid UTF8 accepted")
	}
}
func TestCredentialLimiterBoundsExpiryAndOperationKeys(t *testing.T) {
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	l := newIdentityRateLimiter(func() time.Time { return now })
	for range 20 {
		if !l.Allow("login", "a@example.test", "127.0.0.1:3000") {
			t.Fatal("premature denial")
		}
	}
	if l.Allow("login", "A@example.test", "127.0.0.2:4000") {
		t.Fatal("email limit ignored")
	}
	if !l.Allow("register", "a@example.test", "127.0.0.1:4000") {
		t.Fatal("operation keys not independent")
	}
	now = now.Add(15 * time.Minute)
	if !l.Allow("login", "a@example.test", "127.0.0.1:9000") {
		t.Fatal("expired bucket retained")
	}
	l = newIdentityRateLimiter(func() time.Time { return now })
	for i := range 10000 {
		l.buckets[fmt.Sprint(i)] = identityRateLimitBucket{start: now, last: now, count: 1}
	}
	if l.Allow("login", "new@example.test", "127.0.0.1:9") {
		t.Fatal("capacity exceeded")
	}
	l = newIdentityRateLimiter(func() time.Time { return now })
	for i := range 240 {
		if !l.Allow("login", fmt.Sprintf("%d@example.test", i), fmt.Sprintf("10.0.%d.%d:1", i/250, i%250)) {
			t.Fatalf("global premature denial %d", i)
		}
	}
	if l.Allow("login", "other@example.test", "other:1") {
		t.Fatal("global limit ignored")
	}
}
