package httpapi_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http/httptest"
	"testing"
	"time"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	application "github.com/domabas/domabas/backend/internal/domain/document/services"
	documenthttp "github.com/domabas/domabas/backend/internal/presentation/document/handlers"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

type failingStorage struct{}

func (failingStorage) Create(context.Context, string, document.Document) (document.Document, error) {
	return document.Document{}, errors.New("secret storage detail")
}
func (failingStorage) Get(context.Context, string, string) (document.Document, error) {
	return document.Document{}, errors.New("secret storage detail")
}
func (failingStorage) List(context.Context, string, document.DocumentPageRequest) (document.DocumentPage, error) {
	return document.DocumentPage{}, errors.New("secret storage detail")
}
func (failingStorage) Ping(context.Context) error { return errors.New("secret storage detail") }

func TestLayerCompositionMapsFailures(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	service := application.NewDocumentService(failingStorage{}, time.Now)
	router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(documenthttp.NewDocumentHandler(service, nil, nil, nil, logger), nil, nil, failingStorage{}, nil, nil), transport.NewHTTPIdentityGuard(authenticatorStub{}, permissionStub{}), nil, logger)
	for _, test := range []struct {
		path   string
		status int
		body   string
	}{
		{"/api/v1/documents", 500, "{\"code\":\"internal_error\",\"message\":\"an unexpected error occurred\"}\n"},
		{"/readyz", 503, "{\"code\":\"unavailable\",\"message\":\"a required service is unavailable\"}\n"},
		{"/healthz", 200, "{\"status\":\"ok\"}\n"},
	} {
		response := httptest.NewRecorder()
		request := httptest.NewRequest("GET", test.path, nil)
		request.Header.Set("Authorization", "Bearer "+testToken)
		router.ServeHTTP(response, request)
		if response.Code != test.status || response.Body.String() != test.body {
			t.Fatalf("%s: %d %s", test.path, response.Code, response.Body)
		}
	}
}
