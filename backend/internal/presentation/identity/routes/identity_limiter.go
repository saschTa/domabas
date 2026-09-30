package routes

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

type identityRateLimiter struct {
	mu      sync.Mutex
	now     func() time.Time
	buckets map[string]identityRateLimitBucket
	global  identityRateLimitBucket
}

func newIdentityRateLimiter(now func() time.Time) *identityRateLimiter {
	return &identityRateLimiter{now: now, buckets: make(map[string]identityRateLimitBucket)}
}
func (l *identityRateLimiter) Allow(operation, email, remote string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	for key, b := range l.buckets {
		if now.Sub(b.last) >= 15*time.Minute {
			delete(l.buckets, key)
		}
	}
	host, _, err := net.SplitHostPort(remote)
	if err != nil {
		host = remote
	}
	email = strings.ToLower(strings.TrimSpace(email))
	keys := []string{"source:" + host, "credential:" + operation + ":" + email}
	limits := []int{60, 20}
	windows := []time.Duration{time.Minute, 15 * time.Minute}
	if now.Sub(l.global.start) >= time.Minute {
		l.global = identityRateLimitBucket{start: now}
	}
	if l.global.count >= 240 {
		return false
	}
	needed := 0
	for i, key := range keys {
		b, ok := l.buckets[key]
		if !ok {
			needed++
		}
		if now.Sub(b.start) >= windows[i] {
			b = identityRateLimitBucket{start: now}
		}
		if b.count >= limits[i] {
			return false
		}
	}
	if len(l.buckets)+needed > 10000 {
		return false
	}
	l.global.count++
	for i, key := range keys {
		b := l.buckets[key]
		if now.Sub(b.start) >= windows[i] || b.start.IsZero() {
			b = identityRateLimitBucket{start: now}
		}
		b.count++
		b.last = now
		l.buckets[key] = b
	}
	return true
}
func (l *identityRateLimiter) check(w http.ResponseWriter, r *http.Request, operation, email string) bool {
	if l.Allow(operation, email, r.RemoteAddr) {
		return true
	}
	w.Header().Set("Retry-After", "900")
	writeError(w, 429, "rate_limited", "too many credential attempts; try again later")
	return false
}
