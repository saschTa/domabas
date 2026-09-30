package routes_test

import (
	"io"
	"log/slog"
	"net/url"
	"strings"
	"testing"

	"github.com/domabas/domabas/backend/internal/presentation/document/handlers"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

func TestVocabularyStrictRawQueryOnGetAndHead(t *testing.T) {
	for _, method := range []string{"GET", "HEAD"} {
		t.Run(method, func(t *testing.T) {
			service := &vocabularyStub{}
			logger := slog.New(slog.NewTextHandler(io.Discard, nil))
			router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(handlers.NewDocumentHandler(nil, nil, nil, service, logger), nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(documentAuthenticator{}, &vocabularyClaims{read: true, search: true}), nil, logger)
			for _, query := range []string{
				"", "field=", "field=tag&%66ield=sender", "field=tag&limit=1&%6cimit=2", "field=tag&cursor=a&%63ursor=b",
				"field=tag&query=x&query=", "field=tag&unknown=x", "Field=tag", "field=tag&=x", "field=tag&%FF=x", "field=tag&%ZZ=x",
				"field=tag&query=%C0%AF", "field=tag&query=%ED%A0%80", "field=tag&query=%F4%90%80%80",
				"field=tag&query=%01", "field=tag&query=%7F", "field=tag&query=%C2%80",
				"field=tag&query=" + url.QueryEscape(strings.Repeat("a", 321)),
				"field=tag&query=" + url.QueryEscape(strings.Repeat("😀", 321)),
				"field=tag&cursor=" + strings.Repeat("a", 4097),
				"field=tag&limit=-1", "field=tag&limit=999999999999999999999", "field=tag&query=x;y",
			} {
				response := request(t, router, method, "/api/v1/documents/vocabulary?"+query, "", nil, true, false)
				if response.Code != 400 || service.calls != 0 {
					t.Fatalf("raw query %q: status %d, calls %d", query, response.Code, service.calls)
				}
			}
			for _, query := range []string{"", "\u0085\u0085", "\ufeffAlice\ufeff", strings.Repeat("<", 320), strings.Repeat("😀", 320)} {
				before := service.calls
				response := request(t, router, method, "/api/v1/documents/vocabulary?%66ield=sender&%71uery="+url.QueryEscape(query)+"&limit=50", "", nil, true, false)
				if response.Code != 200 || service.calls != before+1 || service.input.Query != strings.TrimSpace(query) || service.input.Limit != 50 {
					t.Fatalf("valid query failed: status %d, input %+v", response.Code, service.input)
				}
			}
		})
	}
}

func TestVocabularyPasswordRestrictionPrecedesParsingAndClaims(t *testing.T) {
	service := &vocabularyStub{}
	claims := &documentAuthorizer{allow: true}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(handlers.NewDocumentHandler(nil, nil, nil, service, logger), nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(documentAuthenticator{restricted: true}, claims), nil, logger)
	for _, method := range []string{"GET", "HEAD"} {
		response := request(t, router, method, "/api/v1/documents/vocabulary?limit=broken&query=%FF", "", nil, true, false)
		if response.Code != 403 || service.calls != 0 || len(claims.seen) != 0 {
			t.Fatalf("password restriction reached parser/claims/service: %d %d %+v", response.Code, service.calls, claims.seen)
		}
	}
}

func TestSearchExplicitAddressModesValidateBeforeEmptyAddressNormalization(t *testing.T) {
	service := &searchStub{}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	router := httpapi.NewHTTPRouter(httpapi.NewHTTPHandler(handlers.NewDocumentHandler(nil, service, nil, nil, logger), nil, nil, nil, nil, nil), transport.NewHTTPIdentityGuard(documentAuthenticator{}, &searchOnlyAuthorizer{allow: true}), nil, logger)
	for _, body := range []string{
		`{"mode":"fulltext","query":"","sender":"","senderMatch":"unknown"}`,
		`{"mode":"fulltext","query":"","recipient":"","recipientMatch":"unknown"}`,
		`{"mode":"fulltext","query":"","senderMatch":""}`,
		`{"mode":"fulltext","query":"","recipientMatch":null}`,
		`{"mode":"fulltext","query":"","senderMatch":1}`,
		`{"mode":"fulltext","query":"","senderMatch":"exact","senderMatch":"contains"}`,
	} {
		response := request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(body), true, false)
		if response.Code != 400 || service.calls != 0 {
			t.Fatalf("invalid explicit address mode reached service: %s: %d, calls %d", body, response.Code, service.calls)
		}
	}
	for _, test := range []struct {
		body, sender, recipient, senderMode, recipientMode string
	}{
		{`{"mode":"fulltext","query":"","sender":"","recipient":"","senderMatch":"exact","recipientMatch":"exact"}`, "", "", "contains", "contains"},
		{`{"mode":"fulltext","query":"","sender":"\ufeffAlice\ufeff","recipient":"Bob","senderMatch":"exact"}`, "\ufeffAlice\ufeff", "Bob", "exact", "contains"},
		{`{"mode":"fulltext","query":"","sender":"Alice","recipient":"\ufeffBob\ufeff","recipientMatch":"exact"}`, "Alice", "\ufeffBob\ufeff", "contains", "exact"},
	} {
		response := request(t, router, "POST", "/api/v1/documents/search", "application/json", []byte(test.body), true, false)
		input := service.input
		if response.Code != 200 || input.Sender != test.sender || input.Recipient != test.recipient || input.SenderMatch != test.senderMode || input.RecipientMatch != test.recipientMode {
			t.Fatalf("valid independent address modes: %d %+v", response.Code, input)
		}
	}
}
