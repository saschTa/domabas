package routes_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"strings"
	"testing"
	"time"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/handlers"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

const documentID = "00000000-0000-4000-8000-000000000008"

type documentAuthenticator struct{ restricted bool }

func (a documentAuthenticator) Authenticate(context.Context, string) (identity.IdentityPrincipal, error) {
	return identity.IdentityPrincipal{AccountID: "00000000-0000-4000-8000-000000000001", UserID: "00000000-0000-4000-8000-000000000002", SessionDigest: strings.Repeat("a", 64), CredentialRevision: 1, MustChangePassword: a.restricted}, nil
}

type documentAuthorizer struct {
	allow bool
	seen  []identity.IdentityPermission
}

func (a *documentAuthorizer) Allows(_ identity.IdentityPrincipal, claim identity.IdentityPermission) bool {
	a.seen = append(a.seen, claim)
	return a.allow
}

type ingestionStub struct {
	handlers.DocumentIngestionService
	reserved, staged, accepted, abandoned int
	filename                              string
	metadata                              domain.DocumentMetadata
	bytes                                 int
	stageError, errorOnAccept             error
}

func (s *ingestionStub) ReserveUpload(_ context.Context, a domain.DocumentActor) (domain.DocumentUploadReservation, error) {
	s.reserved++
	return domain.DocumentUploadReservation{ID: documentID, AccountID: a.AccountID, UploaderID: a.UserID, ExpiresAt: time.Now().Add(time.Minute)}, nil
}
func (s *ingestionStub) StageUpload(_ context.Context, _ domain.DocumentActor, _ domain.DocumentUploadReservation, filename string, reader io.Reader) (domain.DocumentFileReference, error) {
	s.staged++
	s.filename = filename
	body, err := io.ReadAll(io.LimitReader(reader, domain.MaxFileBytes+1))
	s.bytes = len(body)
	if err != nil {
		return domain.DocumentFileReference{}, err
	}
	if int64(len(body)) > domain.MaxFileBytes {
		return domain.DocumentFileReference{}, domain.ErrTooLarge
	}
	return domain.DocumentFileReference{}, s.stageError
}
func (s *ingestionStub) AcceptUpload(_ context.Context, _ domain.DocumentActor, _ domain.DocumentUploadReservation, metadata domain.DocumentMetadata) (domain.Document, error) {
	s.accepted++
	s.metadata = metadata
	return domain.Document{ID: documentID, Title: metadata.Title, Description: metadata.Description, Kind: metadata.Kind, CreatedAt: time.Now().UTC()}, s.errorOnAccept
}
func (s *ingestionStub) AbandonUpload(context.Context, domain.DocumentActor, domain.DocumentUploadReservation) error {
	s.abandoned++
	return nil
}
func (s *ingestionStub) GetProcessingConfiguration(context.Context, domain.DocumentActor) (domain.DocumentProcessingConfiguration, error) {
	return domain.DefaultConfiguration(), nil
}
func ingestionRouter(service *ingestionStub, authorizer *documentAuthorizer, restricted bool) http.Handler {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	handler := httpapi.NewHTTPHandler(handlers.NewDocumentHandler(nil, service, nil, nil, logger), nil, nil, nil, nil, nil)
	return httpapi.NewHTTPRouter(handler, transport.NewHTTPIdentityGuard(documentAuthenticator{restricted}, authorizer), nil, logger)
}
func request(t *testing.T, router http.Handler, method, path, contentType string, body []byte, authenticated bool, unknownLength bool) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(method, path, bytes.NewReader(body))
	if authenticated {
		r.Header.Set("Authorization", "Bearer test-session")
	}
	if contentType != "" {
		r.Header.Set("Content-Type", contentType)
	}
	if unknownLength {
		r.ContentLength = -1
	}
	response := httptest.NewRecorder()
	router.ServeHTTP(response, r)
	if response.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("protected response can be cached")
	}
	return response
}

type uploadPart struct {
	name, filename, contentType, body string
	headers                           textproto.MIMEHeader
}

func multipartBody(t *testing.T, parts []uploadPart) ([]byte, string) {
	t.Helper()
	var buffer bytes.Buffer
	writer := multipart.NewWriter(&buffer)
	for _, part := range parts {
		headers := part.headers
		if headers == nil {
			headers = textproto.MIMEHeader{}
			disposition := `form-data; name="` + part.name + `"`
			if part.filename != "" {
				disposition += `; filename="` + part.filename + `"`
			}
			headers.Set("Content-Disposition", disposition)
			if part.contentType != "" {
				headers.Set("Content-Type", part.contentType)
			}
		}
		body, err := writer.CreatePart(headers)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = io.WriteString(body, part.body); err != nil {
			t.Fatal(err)
		}
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes(), writer.FormDataContentType()
}
func defaultParts() []uploadPart {
	return []uploadPart{{name: "file", filename: "invoice.pdf", contentType: "application/octet-stream", body: "%PDF-1.7\nfile bytes"}, {name: "metadata", contentType: "application/json", body: `{"title":" Invoice ","tags":["mail"]}`}}
}

func TestNewDocumentClaimsPrecedeUUIDBodyAndMultipartParsing(t *testing.T) {
	cases := []struct {
		method, path string
		claim        identity.IdentityPermission
	}{{"PATCH", "/api/v1/documents/not-a-uuid", identity.DocumentsUpdate}, {"POST", "/api/v1/documents/upload", identity.DocumentsUpload}, {"POST", "/api/v1/documents/search", identity.DocumentsSearch}, {"GET", "/api/v1/documents/not-a-uuid/content", identity.DocumentsDownload}, {"HEAD", "/api/v1/documents/not-a-uuid/content", identity.DocumentsDownload}, {"GET", "/api/v1/documents/not-a-uuid/processing", identity.DocumentsRead}, {"POST", "/api/v1/documents/not-a-uuid/retry", identity.DocumentsRetry}, {"GET", "/api/v1/system/document-processing", identity.SystemDocumentProcessingManage}, {"PUT", "/api/v1/system/document-processing", identity.SystemDocumentProcessingManage}}
	for _, test := range cases {
		t.Run(test.method+" "+test.path, func(t *testing.T) {
			stub := &ingestionStub{}
			authorizer := &documentAuthorizer{}
			router := ingestionRouter(stub, authorizer, false)
			if r := request(t, router, test.method, test.path, "invalid content type", []byte("malformed"), false, false); r.Code != 401 {
				t.Fatalf("anonymous parsed beforeguard: %d %s", r.Code, r.Body)
			}
			r := request(t, router, test.method, test.path, "invalid content type", []byte("malformed"), true, false)
			if r.Code != 403 || len(authorizer.seen) != 1 || authorizer.seen[0] != test.claim {
				t.Fatalf("wrong or extra operation claim: %d %+v %s", r.Code, authorizer.seen, r.Body)
			}
			authorizer.seen = nil
			router = ingestionRouter(stub, authorizer, true)
			r = request(t, router, test.method, test.path, "invalid content type", []byte("malformed"), true, false)
			if r.Code != 403 || !strings.Contains(r.Body.String(), "password_change_required") || len(authorizer.seen) != 0 {
				t.Fatalf("restricted session parsed or authorized: %d %+v %s", r.Code, authorizer.seen, r.Body)
			}
			if stub.reserved != 0 {
				t.Fatal("unauthorized upload reserved storage")
			}
		})
	}
}
func TestMultipartUploadAcceptsEitherOrderAndCleansOnlyUnacceptedReservations(t *testing.T) {
	for _, fileFirst := range []bool{true, false} {
		t.Run(map[bool]string{true: "file_first", false: "metadata_first"}[fileFirst], func(t *testing.T) {
			parts := defaultParts()
			if !fileFirst {
				parts[0], parts[1] = parts[1], parts[0]
			}
			body, contentType := multipartBody(t, parts)
			stub := &ingestionStub{}
			authorizer := &documentAuthorizer{allow: true}
			response := request(t, ingestionRouter(stub, authorizer, false), "POST", "/api/v1/documents/upload", contentType, body, true, false)
			if response.Code != 202 || stub.reserved != 1 || stub.staged != 1 || stub.accepted != 1 || stub.abandoned != 0 || stub.metadata.Title != "Invoice" || stub.filename != "invoice.pdf" {
				t.Fatalf("upload: %d %s %+v", response.Code, response.Body, stub)
			}
			if len(authorizer.seen) != 1 || authorizer.seen[0] != identity.DocumentsUpload {
				t.Fatalf("upload inherited an unrelated claim: %+v", authorizer.seen)
			}
		})
	}
	parts := defaultParts()
	body, contentType := multipartBody(t, parts)
	stub := &ingestionStub{errorOnAccept: domain.ErrDuplicate}
	response := request(t, ingestionRouter(stub, &documentAuthorizer{allow: true}, false), "POST", "/api/v1/documents/upload", contentType, body, true, false)
	if response.Code != 409 || stub.abandoned != 1 {
		t.Fatalf("duplicate cleanup: %d %s %+v", response.Code, response.Body, stub)
	}
}
func TestMultipartRejectsRepeatedMissingUnknownPartsAndMalformedMetadata(t *testing.T) {
	parts := defaultParts()
	cases := map[string][]uploadPart{"missing_metadata": parts[:1], "missing_file": parts[1:], "duplicate_file": {parts[0], parts[0]}, "duplicate_metadata": {parts[0], parts[1], parts[1]}, "third_part": {parts[0], parts[1], {name: "extra", body: "x"}}, "unknown_part": {parts[0], {name: "unknown", body: "x"}}, "metadata_filename": {parts[0], {name: "metadata", filename: "metadata.json", body: `{"title":"x"}`}}, "null_metadata": {parts[0], {name: "metadata", body: `{"title":null}`}}, "duplicate_metadata_field": {parts[0], {name: "metadata", body: `{"title":"x","title":"y"}`}}, "foreign_metadata_field": {parts[0], {name: "metadata", body: `{"title":"x","accountId":"foreign"}`}}}
	for name, test := range cases {
		t.Run(name, func(t *testing.T) {
			body, contentType := multipartBody(t, test)
			stub := &ingestionStub{}
			response := request(t, ingestionRouter(stub, &documentAuthorizer{allow: true}, false), "POST", "/api/v1/documents/upload", contentType, body, true, false)
			if response.Code != 400 || stub.accepted != 0 || stub.abandoned != stub.reserved {
				t.Fatalf("invalid multipart accepted or leaked reservation: %d %s %+v", response.Code, response.Body, stub)
			}
		})
	}
}
func TestMultipartLimitsRejectWithoutAcceptanceAndRecoverStagedFile(t *testing.T) {
	cases := []struct {
		name     string
		mutate   func([]uploadPart) []uploadPart
		epilogue int
		unknown  bool
	}{{name: "file", mutate: func(parts []uploadPart) []uploadPart {
		parts[0].body = strings.Repeat("x", int(domain.MaxFileBytes)+1)
		return parts
	}, unknown: true}, {name: "metadata", mutate: func(parts []uploadPart) []uploadPart {
		parts[1].body = `{"title":"x","description":"` + strings.Repeat("x", 32768) + `"}`
		return parts
	}, unknown: true}, {name: "part_headers", mutate: func(parts []uploadPart) []uploadPart { parts[1].contentType = strings.Repeat("x", 8193); return parts }, unknown: true}, {name: "unknown_length_epilogue", epilogue: int(domain.MaxFileBytes) + (64 << 10), unknown: true}, {name: "known_length_epilogue", epilogue: int(domain.MaxFileBytes) + (64 << 10)}}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			parts := defaultParts()
			if test.mutate != nil {
				parts = test.mutate(parts)
			}
			body, contentType := multipartBody(t, parts)
			if test.epilogue > 0 {
				body = append(body, bytes.Repeat([]byte{'x'}, test.epilogue)...)
			}
			stub := &ingestionStub{}
			response := request(t, ingestionRouter(stub, &documentAuthorizer{allow: true}, false), "POST", "/api/v1/documents/upload", contentType, body, true, test.unknown)
			if response.Code != 413 || stub.accepted != 0 || stub.abandoned != stub.reserved {
				t.Fatalf("oversize accepted or failed cleanup: %d %s %+v", response.Code, response.Body, stub)
			}
		})
	}
}
func TestNewJSONRoutesRejectMalformedBeforeDomainCalls(t *testing.T) {
	cases := []struct{ method, path, body string }{{"PATCH", "/api/v1/documents/" + documentID, `{"title":null}`}, {"PATCH", "/api/v1/documents/" + documentID, `{"title":"x","title":"y"}`}, {"PATCH", "/api/v1/documents/" + documentID, `{"tags":[null]}`}, {"POST", "/api/v1/documents/search", `{"query":"x","mode":"semantic","limit":2.5}`}, {"PUT", "/api/v1/system/document-processing", `{"language":"eng","segmentation":"auto","engine":"arbitrary"}`}, {"POST", "/api/v1/documents/" + documentID + "/retry", `{}`}}
	for _, test := range cases {
		t.Run(test.method+test.path+test.body, func(t *testing.T) {
			response := request(t, ingestionRouter(&ingestionStub{}, &documentAuthorizer{allow: true}, false), test.method, test.path, "application/json", []byte(test.body), true, false)
			var envelope map[string]any
			if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil {
				t.Fatal(err)
			}
			if response.Code != 400 || envelope["code"] != "invalid_request" {
				t.Fatalf("invalid JSON reached domain: %d %s", response.Code, response.Body)
			}
		})
	}
}
