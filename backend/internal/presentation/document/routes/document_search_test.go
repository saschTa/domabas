package routes_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/handlers"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

type searchOnlyAuthorizer struct{ allow bool }

func (a *searchOnlyAuthorizer) Allows(_ identity.IdentityPrincipal, claim identity.IdentityPermission) bool {
	return a.allow && claim == identity.DocumentsSearch
}

func TestSearchKindArrayHTTPValidation(t *testing.T) {
	service := &searchStub{}
	policy := &searchOnlyAuthorizer{allow: true}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(handlers.NewDocumentHandler(nil, service, nil, nil, logger), nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(documentAuthenticator{}, policy), nil, logger)
	for _, test := range []struct {
		array string
		want  []string
	}{
		{`[]`, []string{}},
		{`["email"]`, []string{"email"}},
		{`["letter","document","letter"]`, []string{"document", "letter"}},
		{`["letter","email","document"]`, []string{}},
	} {
		response := request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(`{"mode":"hybrid","query":"","kinds":`+test.array+`}`), true, false)
		if response.Code != 200 || !slices.Equal(service.input.Kinds, test.want) {
			t.Fatalf("kinds %s: %d %s %+v", test.array, response.Code, response.Body.String(), service.input)
		}
	}
	for _, invalid := range []string{`null`, `"email"`, `[null]`, `[1]`, `["pdf"]`, `[""]`, `["EMAIL"]`, `["email","email","email","email"]`} {
		response := request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(`{"mode":"fulltext","query":"","kinds":`+invalid+`}`), true, false)
		if response.Code != 400 {
			t.Fatalf("invalid kinds accepted %s: %d %s", invalid, response.Code, response.Body.String())
		}
	}
}

type searchStub struct {
	handlers.DocumentIngestionService
	input   domain.DocumentSearchInput
	calls   int
	failure error
	ctx     context.Context
}

func (s *searchStub) Search(ctx context.Context, _ domain.DocumentActor, input domain.DocumentSearchInput) (domain.DocumentSearchResults, error) {
	s.ctx = ctx
	var err error
	input, err = input.Normalize()
	if err != nil {
		return domain.DocumentSearchResults{}, err
	}
	s.calls++
	s.input = input
	return domain.DocumentSearchResults{Items: []domain.DocumentSearchResult{}}, s.failure
}

func TestSearchDeadlineAllowsEmbeddingAndBothDatabasePasses(t *testing.T) {
	service := &searchStub{}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(handlers.NewDocumentHandler(nil, service, nil, nil, logger), nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(documentAuthenticator{}, &searchOnlyAuthorizer{allow: true}), nil, logger)
	response := request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(`{"mode":"hybrid","query":"invoice payment"}`), true, false)
	if response.Code != 200 || service.ctx == nil {
		t.Fatalf("search did not reach the service: %d", response.Code)
	}
	deadline, ok := service.ctx.Deadline()
	remaining := time.Until(deadline)
	if !ok || remaining <= 29*time.Second || remaining > 30*time.Second || service.ctx.Err() != context.Canceled {
		t.Fatalf("search deadline: %v, remaining %v, context error %v", deadline, remaining, service.ctx.Err())
	}
}

func TestSearchFailureLogsCodeWithoutPrivateCriteria(t *testing.T) {
	service := &searchStub{failure: domain.ErrUnavailable}
	var logs bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logs, nil))
	router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(handlers.NewDocumentHandler(nil, service, nil, nil, logger), nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(documentAuthenticator{}, &searchOnlyAuthorizer{allow: true}), nil, logger)
	response := request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(`{"mode":"hybrid","query":"private query","tags":["private tag"],"sender":"private sender","cursor":"private cursor"}`), true, false)
	if response.Code != 503 || !strings.Contains(response.Body.String(), "unavailable") {
		t.Fatalf("unavailable response: %d %s", response.Code, response.Body.String())
	}
	var record map[string]any
	if err := json.Unmarshal(logs.Bytes(), &record); err != nil {
		t.Fatal(err)
	}
	if record["msg"] != "document search failed" || record["status"] != float64(503) || record["code"] != "unavailable" {
		t.Fatalf("missing search diagnostics: %v", record)
	}
	if strings.Contains(logs.String(), "private") {
		t.Fatal("search logged private request contents")
	}
}

func TestSearchOnlyClaimDoesNotGrantOtherDocumentReads(t *testing.T) {
	service := &searchStub{}
	policy := &searchOnlyAuthorizer{allow: true}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(handlers.NewDocumentHandler(nil, service, nil, nil, logger), nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(documentAuthenticator{}, policy), nil, logger)
	response := request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(`{"mode":"fulltext","query":"İ Σ 😀","sender":"%_sender","recipient":"bcc","sort":"title","limit":12}`), true, false)
	if response.Code != 200 || service.calls != 1 || service.input.Query != "İ Σ 😀" || service.input.Sender != "%_sender" {
		t.Fatalf("search-only sparse request failed: %d %s %+v", response.Code, response.Body.String(), service.input)
	}
	response = request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(`{"mode":"hybrid","query":"invioce"}`), true, false)
	if response.Code != 200 || service.calls != 2 || service.input.Mode != "hybrid" {
		t.Fatalf("hybrid search-only request failed: %d %s", response.Code, response.Body.String())
	}
	for _, path := range []string{"/api/v1/documents", "/api/v1/documents/" + documentID, "/api/v1/documents/" + documentID + "/content", "/api/v1/documents/" + documentID + "/ocr"} {
		response := request(t, router, "GET", path, "", nil, true, false)
		if response.Code != http.StatusForbidden {
			t.Fatalf("search grants unrelated read %s: %d", path, response.Code)
		}
	}
	for _, body := range []string{
		`{"mode":"fulltext","query":"","cursor":null}`, `{"mode":"fulltext","query":"","cursor":""}`,
		`{"mode":"fulltext","query":"","cursor":5}`, `{"mode":"fulltext","query":"","cursor":"a","offset":1}`,
		`{"mode":"fulltext","query":"","sort":null}`, `{"mode":"fulltext","query":"","sort":"unknown"}`,
		`{"mode":"fulltext","query":"","sender":"a","sender":"b"}`, `{"mode":"fulltext","query":"","recipient":[]}`,
		`{"mode":"fulltext","query":"\ud800"}`, `{"mode":"fulltext","query":"","extra":true}`,
	} {
		response := request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(body), true, false)
		if response.Code != 400 {
			t.Fatalf("invalid search accepted %s: %d %s", body, response.Code, response.Body.String())
		}
	}
	policy.allow = false
	response = request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(`{"mode":"fulltext","query":"invoice","cursor":"later-page"}`), true, false)
	if response.Code != 403 || service.calls != 2 {
		t.Fatalf("later-page claim revocation ignored: %d %d", response.Code, service.calls)
	}
}
