package routes_test

import (
	"context"
	"io"
	"log/slog"
	"testing"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/handlers"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

type vocabularyStub struct {
	calls int
	input domain.DocumentVocabularyInput
}

func (service *vocabularyStub) List(_ context.Context, _ domain.DocumentActor, input domain.DocumentVocabularyInput) (domain.DocumentVocabularyPage, error) {
	var err error
	input, err = input.Normalize()
	if err != nil {
		return domain.DocumentVocabularyPage{}, err
	}
	service.calls++
	service.input = input
	return domain.DocumentVocabularyPage{}, nil
}

type vocabularyClaims struct {
	read, search bool
}

func (claims *vocabularyClaims) Allows(_ identity.IdentityPrincipal, claim identity.IdentityPermission) bool {
	return claim == identity.DocumentsRead && claims.read || claim == identity.DocumentsSearch && claims.search
}

func TestVocabularyQueryValidationAndGuardOrdering(t *testing.T) {
	service := &vocabularyStub{}
	claims := &vocabularyClaims{read: true, search: true}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(handlers.NewDocumentHandler(nil, nil, nil, service, logger), nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(documentAuthenticator{}, claims), nil, logger)
	for _, method := range []string{"GET", "HEAD"} {
		response := request(t, router, method, "/api/v1/documents/vocabulary?field=tag&query=", "", nil, true, false)
		if response.Code != 200 || service.input.Query != "" || service.input.Limit != 40 {
			t.Fatalf("explicit empty query: %d %s %+v", response.Code, response.Body.String(), service.input)
		}
	}
	for _, query := range []string{
		"field=tag&query=x&%71uery=y", "field=tag&field=sender", "field=tag&Query=x", "field=tag&libraryId=x",
		"field=tag&query=%FF", "field=tag&query=%ZZ", "field=tag&query=x%00y", "field=tag&query=x;y",
		"field=tag&cursor=", "field=tag&limit=", "field=tag&limit=0", "field=tag&limit=51", "field=tag&limit=1.5", "field=unknown",
	} {
		response := request(t, router, "GET", "/api/v1/documents/vocabulary?"+query, "", nil, true, false)
		if response.Code != 400 {
			t.Fatalf("invalid query %q: %d %s", query, response.Code, response.Body.String())
		}
	}
	if service.calls != 2 {
		t.Fatalf("invalid query reached service: %d", service.calls)
	}
	for _, method := range []string{"GET", "HEAD"} {
		for _, allowed := range [][2]bool{{true, false}, {false, true}, {false, false}} {
			claims.read, claims.search = allowed[0], allowed[1]
			response := request(t, router, method, "/api/v1/documents/vocabulary?limit=broken", "", nil, true, false)
			if response.Code != 403 {
				t.Fatalf("%s claims %v validated before authorization: %d", method, allowed, response.Code)
			}
		}
		response := request(t, router, method, "/api/v1/documents/vocabulary?limit=broken", "", nil, false, false)
		if response.Code != 401 {
			t.Fatalf("%s validated before authentication: %d", method, response.Code)
		}
	}
}
