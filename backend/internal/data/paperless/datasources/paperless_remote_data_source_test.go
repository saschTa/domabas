package datasources

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

func TestUserSourceAuthenticationOriginalsAndPacing(t *testing.T) {
	var mu sync.Mutex
	var times []time.Time
	var paths []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" || r.Header.Get("Authorization") != "Token test-token" || r.Header.Get("Accept") != "application/json; version=9" {
			t.Error("invalid read-only protocol headers")
		}
		mu.Lock()
		times = append(times, time.Now())
		paths = append(paths, r.URL.RequestURI())
		mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"count":0,"next":null,"results":[]}`)
	}))
	defer server.Close()
	s := NewPaperlessRemoteDataSource()
	c := m.PaperlessConnection{ServerURL: server.URL + "/paperless", Token: "test-token"}
	if _, err := s.Page(t.Context(), c, 1); err != nil {
		t.Fatal(err)
	}
	body, err := s.Download(t.Context(), c, 12)
	if err != nil {
		t.Fatal(err)
	}
	body.Close()
	if len(times) != 2 || times[1].Sub(times[0]) < 95*time.Millisecond {
		t.Fatalf("unpaced requests: %v", times)
	}
	if paths[1] != "/paperless/api/documents/12/download/?original=true" {
		t.Fatal(paths)
	}
}
func TestRejectsUnsafeEndpointsRedirectsSecretsAndBodies(t *testing.T) {
	var leaked bool
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { leaked = true }))
	defer target.Close()
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, http.StatusFound) }))
	defer source.Close()
	s := NewPaperlessRemoteDataSource()
	_, err := s.Page(t.Context(), m.PaperlessConnection{ServerURL: source.URL, Token: "sensitive-token"}, 1)
	if err == nil || leaked || strings.Contains(err.Error(), "sensitive-token") {
		t.Fatalf("unsafe redirect: %v", err)
	}
	_, err = s.Page(t.Context(), m.PaperlessConnection{ServerURL: "http://169.254.169.254", Token: "secret"}, 1)
	var failure m.PaperlessFailure
	if !errors.As(err, &failure) || failure.Code != "server_not_allowed" || leaked {
		t.Fatal(err)
	}
	for _, token := range []string{"", "line\r\nbreak", strings.Repeat("x", 257)} {
		_, err = s.Page(t.Context(), m.PaperlessConnection{ServerURL: source.URL, Token: token}, 1)
		if !errors.As(err, &failure) || failure.Code != "invalid_request" {
			t.Fatal(err)
		}
	}
	oversize := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, strings.Repeat(" ", (1<<20)+1)) }))
	defer oversize.Close()
	s = NewPaperlessRemoteDataSource()
	_, err = s.Page(t.Context(), m.PaperlessConnection{ServerURL: oversize.URL, Token: "x"}, 1)
	if !errors.As(err, &failure) || failure.Code != "source_incompatible" {
		t.Fatal(err)
	}
}
func TestRejectsInvalidUserURLsAndCancelsPacing(t *testing.T) {
	for _, url := range []string{"file:///etc/passwd", "http://user:password@host", "http://host/?query=1", "http://host/#fragment", "http://host:0", "http://host:99999", "http://host/a/../b", "http://host/%2fsecret", "http://host/\\test"} {
		if _, err := normalizeServerURL(url); err == nil {
			t.Errorf("accepted %s", url)
		}
	}
	s := NewPaperlessRemoteDataSource()
	s.nextRequest = time.Now().Add(time.Hour)
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	start := time.Now()
	_, err := s.Page(ctx, m.PaperlessConnection{ServerURL: "https://paperless.example.test", Token: "secret"}, 1)
	if err == nil || time.Since(start) > time.Second {
		t.Fatal("pacing failed to cancel")
	}
}

func TestPaperlessNameLeavesValueValidationToMetadataMapping(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"id":10,"name":" "}`)
	}))
	defer server.Close()
	source := NewPaperlessRemoteDataSource()
	connection := m.PaperlessConnection{ServerURL: server.URL, Token: "test-token"}
	name, err := source.Name(t.Context(), connection, "tags", 10)
	if err != nil || name != " " {
		t.Fatal("blank metadata rejected before fallback", name, err)
	}
	_, err = source.Name(t.Context(), connection, "tags", 11)
	if !errors.Is(err, m.PaperlessFailure{Code: "source_incompatible"}) {
		t.Fatal("mismatched source identity accepted", err)
	}
}
