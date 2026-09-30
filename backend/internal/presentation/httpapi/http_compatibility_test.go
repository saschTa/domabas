package httpapi_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	documenthttp "github.com/domabas/domabas/backend/internal/presentation/document/handlers"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

const accountID = "e9d6f5eb-151a-4889-b70d-ad7ce0f98e03"
const testToken = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

const documentID = "f7974618-e835-4d61-8693-1e288b013b8d"

var createdAt = time.Date(2026, 9, 17, 10, 0, 0, 0, time.UTC)

type serviceStub struct {
	createCalls int
	getCalls    int
	listCalls   int
	input       document.DocumentCreateInput
	page        document.DocumentPageRequest
	id          string
	ctx         context.Context
	items       []document.Document
	err         error
	panic       bool
}

func (service *serviceStub) Create(ctx context.Context, account string, input document.DocumentCreateInput) (document.Document, error) {
	if account != accountID {
		panic("missing account scope")
	}
	service.createCalls++
	service.input, service.ctx = input, ctx
	if service.panic {
		panic("private panic details")
	}
	return document.Document{ID: documentID, Title: input.Title, Description: input.Description, CreatedAt: createdAt}, service.err
}

func (service *serviceStub) Get(ctx context.Context, account, id string) (document.Document, error) {
	if account != accountID {
		panic("missing account scope")
	}
	service.getCalls++
	service.id, service.ctx = id, ctx
	return document.Document{ID: id, Title: "Stored", CreatedAt: createdAt}, service.err
}

func (service *serviceStub) List(ctx context.Context, account string, page document.DocumentPageRequest) (document.DocumentPage, error) {
	if account != accountID {
		panic("missing account scope")
	}
	service.listCalls++
	service.page, service.ctx = page, ctx
	return document.DocumentPage{Items: service.items, Total: int64(len(service.items))}, service.err
}

type probeStub struct {
	ctx   context.Context
	calls int
	err   error
}

func (probe *probeStub) Ping(ctx context.Context) error {
	probe.ctx = ctx
	probe.calls++
	return probe.err
}

func testRouter(service documenthttp.DocumentService, probe *probeStub, origins ...string) http.Handler {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(documenthttp.NewDocumentHandler(service, nil, nil, nil, logger), nil, nil, probe, nil, nil), transport.NewHTTPIdentityGuard(authenticatorStub{}, permissionStub{}), origins, logger)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Header.Set("Authorization", "Bearer "+testToken)
		router.ServeHTTP(w, r)
	})
}

func assertError(t *testing.T, response *httptest.ResponseRecorder, status int, code, message string) {
	t.Helper()
	var body contract.Error
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid error body: %v: %s", err, response.Body)
	}
	if response.Code != status || response.Header().Get("Content-Type") != "application/json" || body.Code != code || body.Message != message {
		t.Fatalf("error response: status %d, headers %v, body %s; want %d %s %q", response.Code, response.Header(), response.Body, status, code, message)
	}
}

func TestDocumentJSONCompatibility(t *testing.T) {
	const shapeError = "body must be an object with a string title and optional string description"
	const objectError = "body must contain exactly one JSON object without null fields"
	const titleError = "title must contain 1 to 200 characters and cannot be blank"
	base := `{"title":"Valid"}`
	limitBody := base + strings.Repeat(" ", 32*1024-len(base))
	for _, test := range []struct {
		name        string
		body        string
		contentType string
		status      int
		message     string
		title       string
		description string
	}{
		{"valid", base, "application/json", 201, "", "Valid", ""},
		{"media parameters", `{"title":"Valid","description":"Text"}`, "application/json; charset=utf-8", 201, "", "Valid", "Text"},
		{"string duplicates", `{"title":"first","title":"last","description":"first","description":"last"}`, "application/json", 201, "", "last", "last"},
		{"null then string", `{"title":null,"title":"last","description":null,"description":"last"}`, "application/json", 201, "", "last", "last"},
		{"exact limit", limitBody, "application/json", 201, "", "Valid", ""},
		{"over limit", limitBody + " ", "application/json", 413, "request body exceeds 32 KiB", "", ""},
		{"missing media type", base, "", 415, "Content-Type must be application/json", "", ""},
		{"wrong media type", base, "text/plain", 415, "Content-Type must be application/json", "", ""},
		{"invalid media type", base, "application/json; broken", 415, "Content-Type must be application/json", "", ""},
		{"empty", "", "application/json", 400, shapeError, "", ""},
		{"malformed", `{"title":`, "application/json", 400, shapeError, "", ""},
		{"missing title", `{}`, "application/json", 400, shapeError, "", ""},
		{"null object", `null`, "application/json", 400, shapeError, "", ""},
		{"array", `[]`, "application/json", 400, shapeError, "", ""},
		{"string", `"text"`, "application/json", 400, shapeError, "", ""},
		{"number", `42`, "application/json", 400, shapeError, "", ""},
		{"boolean", `true`, "application/json", 400, shapeError, "", ""},
		{"null title", `{"title":null}`, "application/json", 400, shapeError, "", ""},
		{"numeric title", `{"title":42}`, "application/json", 400, shapeError, "", ""},
		{"object description", `{"title":"Valid","description":{}}`, "application/json", 400, shapeError, "", ""},
		{"null description", `{"title":"Valid","description":null}`, "application/json", 400, objectError, "", ""},
		{"unknown field", `{"title":"Valid","extra":"value"}`, "application/json", 400, shapeError, "", ""},
		{"mixed-case title", `{"Title":"Valid"}`, "application/json", 400, "body contains an unknown field", "", ""},
		{"mixed-case description", `{"title":"Valid","Description":"Text"}`, "application/json", 400, "body contains an unknown field", "", ""},
		{"trailing object", base + `{}`, "application/json", 400, objectError, "", ""},
		{"trailing garbage", base + `x`, "application/json", 400, objectError, "", ""},
		{"invalid UTF8", "{\"title\":\"\xff\"}", "application/json", 400, shapeError, "", ""},
		{"earlier numeric title", `{"title":42,"title":"last"}`, "application/json", 400, shapeError, "", ""},
		{"earlier object description", `{"title":"Valid","description":{},"description":"last"}`, "application/json", 400, shapeError, "", ""},
		{"final null title", `{"title":"first","title":null}`, "application/json", 400, shapeError, "", ""},
		{"final null description", `{"title":"Valid","description":"first","description":null}`, "application/json", 400, objectError, "", ""},
		{"blank title", `{"title":"  "}`, "application/json", 400, titleError, "", ""},
		{"untrimmed title limit", `{"title":" ` + strings.Repeat("x", 199) + ` "}`, "application/json", 400, titleError, "", ""},
		{"Unicode title limit", `{"title":"` + strings.Repeat("界", 200) + `"}`, "application/json", 201, "", strings.Repeat("界", 200), ""},
		{"long title", `{"title":"` + strings.Repeat("界", 201) + `"}`, "application/json", 400, titleError, "", ""},
		{"long description", `{"title":"Valid","description":"` + strings.Repeat("x", 4001) + `"}`, "application/json", 400, "description must contain at most 4000 characters", "", ""},
	} {
		t.Run(test.name, func(t *testing.T) {
			service := &serviceStub{}
			router := testRouter(service, &probeStub{})
			request := httptest.NewRequest(http.MethodPost, "/api/v1/documents", strings.NewReader(test.body))
			request.Header.Set("Content-Type", test.contentType)
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			if test.status != http.StatusCreated {
				code := "invalid_request"
				if test.status == http.StatusUnsupportedMediaType {
					code = "unsupported_media_type"
				} else if test.status == http.StatusRequestEntityTooLarge {
					code = "body_too_large"
				}
				assertError(t, response, test.status, code, test.message)
				if service.createCalls != 0 {
					t.Fatal("invalid request reached service")
				}
				return
			}
			var body contract.Document
			if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if response.Code != test.status || service.createCalls != 1 || service.input.Title != test.title || service.input.Description != test.description || body.Title != test.title || body.Description != test.description || body.Id.String() != documentID || !body.CreatedAt.Equal(createdAt) {
				t.Fatalf("status %d, input %+v, calls %d, response %s", response.Code, service.input, service.createCalls, response.Body)
			}
		})
	}
}

func TestGeneratedRoutesAndPagination(t *testing.T) {
	for _, test := range []struct {
		name   string
		method string
		path   string
		status int
		calls  string
		page   document.DocumentPageRequest
		allow  string
	}{
		{"default list", "GET", "/api/v1/documents", 200, "list", document.DocumentPageRequest{Limit: 50}, ""},
		{"minimum limit", "GET", "/api/v1/documents?limit=1&offset=0", 200, "list", document.DocumentPageRequest{Limit: 1}, ""},
		{"maximum limit", "GET", "/api/v1/documents?limit=100&offset=12", 200, "list", document.DocumentPageRequest{Limit: 100, Offset: 12}, ""},
		{"limit too small", "GET", "/api/v1/documents?limit=0", 400, "", document.DocumentPageRequest{}, ""},
		{"limit too large", "GET", "/api/v1/documents?limit=101", 400, "", document.DocumentPageRequest{}, ""},
		{"negative offset", "GET", "/api/v1/documents?offset=-1", 400, "", document.DocumentPageRequest{}, ""},
		{"invalid integer", "GET", "/api/v1/documents?limit=invalid", 400, "", document.DocumentPageRequest{}, ""},
		{"get document", "GET", "/api/v1/documents/" + documentID, 200, "get", document.DocumentPageRequest{}, ""},
		{"head document", "HEAD", "/api/v1/documents/" + documentID, 200, "get", document.DocumentPageRequest{}, ""},
		{"invalid UUID", "GET", "/api/v1/documents/invalid", 400, "", document.DocumentPageRequest{}, ""},
		{"health", "GET", "/healthz", 200, "", document.DocumentPageRequest{}, ""},
		{"readiness", "GET", "/readyz", 200, "probe", document.DocumentPageRequest{}, ""},
		{"wrong method", "PUT", "/api/v1/documents", 405, "", document.DocumentPageRequest{}, "GET, HEAD, POST"},
		{"post health", "POST", "/healthz", 405, "", document.DocumentPageRequest{}, "GET, HEAD"},
		{"prefix boundary", "POST", "/api/v1/documents-archive", 404, "", document.DocumentPageRequest{}, ""},
		{"encoded separator", "POST", "/api%2Fv1/documents", 404, "", document.DocumentPageRequest{}, ""},
		{"duplicate slash", "POST", "/api//v1/documents", 307, "", document.DocumentPageRequest{}, ""},
	} {
		t.Run(test.name, func(t *testing.T) {
			service, probe := &serviceStub{}, &probeStub{}
			response := httptest.NewRecorder()
			testRouter(service, probe).ServeHTTP(response, httptest.NewRequest(test.method, test.path, nil))
			if response.Code != test.status || response.Header().Get("Allow") != test.allow {
				t.Fatalf("status %d, Allow %q, response %s", response.Code, response.Header().Get("Allow"), response.Body)
			}
			wantList, wantGet, wantProbe := 0, 0, 0
			switch test.calls {
			case "list":
				wantList = 1
				if service.page != test.page || response.Body.String() != "{\"items\":[],\"total\":0}\n" {
					t.Fatalf("page %+v, response %s", service.page, response.Body)
				}
			case "get":
				wantGet = 1
				var body contract.Document
				if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil || body.Id.String() != documentID || body.Title != "Stored" || service.id != documentID {
					t.Fatalf("get mapping: id %q, response %s, error %v", service.id, response.Body, err)
				}
			case "probe":
				wantProbe = 1
			}
			if service.createCalls != 0 || service.listCalls != wantList || service.getCalls != wantGet || probe.calls != wantProbe {
				t.Fatalf("calls: create %d, list %d, get %d, probe %d", service.createCalls, service.listCalls, service.getCalls, probe.calls)
			}
			if test.status == http.StatusBadRequest {
				message := "limit must be between 1 and 100 and offset must be nonnegative"
				if test.name == "invalid integer" || test.name == "invalid UUID" {
					message = "request parameters or body are invalid"
				}
				assertError(t, response, 400, "invalid_request", message)
			}
		})
	}
}

func TestPopulatedListMapsDomainValues(t *testing.T) {
	service := &serviceStub{items: []document.Document{{ID: documentID, Title: "Stored", Description: "Details", CreatedAt: createdAt}}}
	response := httptest.NewRecorder()
	testRouter(service, &probeStub{}).ServeHTTP(response, httptest.NewRequest("GET", "/api/v1/documents", nil))
	var body contract.DocumentList
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if response.Code != 200 || body.Total != 1 || len(body.Items) != 1 || body.Items[0].Id.String() != documentID || body.Items[0].Title != "Stored" || body.Items[0].Description != "Details" || !body.Items[0].CreatedAt.Equal(createdAt) {
		t.Fatalf("list response: %d %s", response.Code, response.Body)
	}
}

func TestRootHeadersAndGlobalOptions(t *testing.T) {
	for _, test := range []struct {
		method string
		path   string
		origin string
		status int
	}{
		{"GET", "/healthz", "https://allowed.example", 200},
		{"POST", "/api/v1/documents", "https://allowed.example", 415},
		{"OPTIONS", "/missing", "https://allowed.example", 204},
		{"OPTIONS", "/missing", "https://other.example", 204},
		{"GET", "/missing", "", 404},
	} {
		service, probe := &serviceStub{}, &probeStub{}
		request := httptest.NewRequest(test.method, test.path, nil)
		request.Header.Set("Origin", test.origin)
		response := httptest.NewRecorder()
		testRouter(service, probe, "https://allowed.example").ServeHTTP(response, request)
		if response.Code != test.status || response.Header().Get("X-Content-Type-Options") != "nosniff" || response.Header().Get("Vary") != "Origin" {
			t.Fatalf("root headers: %d %v", response.Code, response.Header())
		}
		wantOrigin, wantMethods, wantHeaders, wantCredentials := "", "", "", ""
		if test.origin == "https://allowed.example" {
			wantOrigin, wantMethods, wantHeaders = test.origin, "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS", "Content-Type, Authorization, X-Domabas-Browser"
			wantCredentials = "true"
		}
		if response.Header().Get("Access-Control-Allow-Origin") != wantOrigin || response.Header().Get("Access-Control-Allow-Methods") != wantMethods || response.Header().Get("Access-Control-Allow-Headers") != wantHeaders || response.Header().Get("Access-Control-Allow-Credentials") != wantCredentials {
			t.Fatalf("CORS headers: %v", response.Header())
		}
		if service.createCalls+service.getCalls+service.listCalls+probe.calls != 0 {
			t.Fatal("request unexpectedly reached a dependency")
		}
	}
}

func TestRequestAndReadinessDeadlines(t *testing.T) {
	for _, test := range []struct {
		path    string
		timeout time.Duration
	}{
		{"/api/v1/documents", 10 * time.Second},
		{"/readyz", 2 * time.Second},
	} {
		service, probe := &serviceStub{}, &probeStub{}
		response := httptest.NewRecorder()
		testRouter(service, probe).ServeHTTP(response, httptest.NewRequest("GET", test.path, nil))
		ctx := service.ctx
		if test.path == "/readyz" {
			ctx = probe.ctx
		}
		deadline, ok := ctx.Deadline()
		remaining := time.Until(deadline)
		if response.Code != 200 || !ok || remaining <= test.timeout-time.Second || remaining > test.timeout || ctx.Err() != context.Canceled {
			t.Fatalf("%s: status %d, deadline %v, remaining %v, context error %v", test.path, response.Code, ok, remaining, ctx.Err())
		}
	}
}

func TestFailuresKeepContractErrors(t *testing.T) {
	for _, test := range []struct {
		name    string
		method  string
		path    string
		err     error
		panic   bool
		status  int
		code    string
		message string
	}{
		{"create failure", "POST", "/api/v1/documents", errors.New("private database detail"), false, 500, "internal_error", "an unexpected error occurred"},
		{"get failure", "GET", "/api/v1/documents/" + documentID, errors.New("private database detail"), false, 500, "internal_error", "an unexpected error occurred"},
		{"list failure", "GET", "/api/v1/documents", errors.New("private database detail"), false, 500, "internal_error", "an unexpected error occurred"},
		{"not found", "GET", "/api/v1/documents/" + documentID, document.ErrNotFound, false, 404, "not_found", "document not found"},
		{"create service validation", "POST", "/api/v1/documents", document.DocumentValidationError{Message: "service validation"}, false, 400, "invalid_request", "service validation"},
		{"list service validation", "GET", "/api/v1/documents", document.DocumentValidationError{Message: "service validation"}, false, 400, "invalid_request", "service validation"},
		{"panic", "POST", "/api/v1/documents", nil, true, 500, "internal_error", "an unexpected error occurred"},
		{"unavailable", "GET", "/readyz", errors.New("private readiness details"), false, 503, "unavailable", "a required service is unavailable"},
	} {
		t.Run(test.name, func(t *testing.T) {
			service := &serviceStub{err: test.err, panic: test.panic}
			request := httptest.NewRequest(test.method, test.path, strings.NewReader(`{"title":"Valid"}`))
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			testRouter(service, &probeStub{err: test.err}).ServeHTTP(response, request)
			assertError(t, response, test.status, test.code, test.message)
		})
	}
}

func TestDirectHandlerRejectsMissingBody(t *testing.T) {
	service := &serviceStub{}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	result, err := documenthttp.NewDocumentHandler(service, nil, nil, nil, logger).CreateDocument(principalContext(t), contract.CreateDocumentRequestObject{})
	if err != nil {
		t.Fatal(err)
	}
	response := httptest.NewRecorder()
	if err := result.VisitCreateDocumentResponse(response); err != nil {
		t.Fatal(err)
	}
	assertError(t, response, 400, "invalid_request", "request body is required")
	if service.createCalls != 0 {
		t.Fatal("missing body reached service")
	}
}

type failingReader struct{}

func (failingReader) Read([]byte) (int, error) { return 0, errors.New("private read failure") }

func TestBodyReadFailureIsSanitized(t *testing.T) {
	service := &serviceStub{}
	request := httptest.NewRequest("POST", "/api/v1/documents", failingReader{})
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	testRouter(service, &probeStub{}).ServeHTTP(response, request)
	assertError(t, response, 400, "invalid_request", "cannot read request body")
	if service.createCalls != 0 {
		t.Fatal("unreadable body reached service")
	}
}

type authenticatorStub struct{}

func (authenticatorStub) Authenticate(context.Context, string) (identity.IdentityPrincipal, error) {
	return identity.IdentityPrincipal{UserID: documentID, AccountID: accountID, Role: identity.Admin, IsOwner: true, Permissions: []identity.IdentityPermission{identity.DocumentsRead, identity.DocumentsCreate, identity.UsersManage}}, nil
}

type permissionStub struct{}

func (permissionStub) Allows(identity.IdentityPrincipal, identity.IdentityPermission) bool {
	return true
}
func principalContext(t *testing.T) context.Context {
	t.Helper()
	var ctx context.Context
	request := httptest.NewRequest("GET", "/api/v1/auth/session", nil)
	request.Header.Set("Authorization", "Bearer "+testToken)
	transport.NewHTTPIdentityGuard(authenticatorStub{}, permissionStub{}).Require("")(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) { ctx = r.Context() })).ServeHTTP(httptest.NewRecorder(), request)
	if ctx == nil {
		t.Fatal("test authentication did not establish principal")
	}
	return ctx
}
