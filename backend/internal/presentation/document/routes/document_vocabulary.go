package routes

import (
	"net/http"
	"net/url"
	"strconv"
	"unicode/utf8"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

func validVocabularyQuery(r *http.Request) bool {
	query, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil {
		return false
	}
	for name, values := range query {
		if !utf8.ValidString(name) || len(values) != 1 || !utf8.ValidString(values[0]) {
			return false
		}
		switch name {
		case "field", "query", "limit", "cursor":
		default:
			return false
		}
	}
	input := domain.DocumentVocabularyInput{Field: query.Get("field"), Query: query.Get("query"), Cursor: query.Get("cursor"), Limit: 40}
	if values, present := query["cursor"]; present && values[0] == "" {
		return false
	}
	if values, present := query["limit"]; present {
		input.Limit, err = strconv.Atoi(values[0])
		if err != nil || input.Limit < 1 || input.Limit > 50 {
			return false
		}
	}
	_, err = input.Normalize()
	return err == nil
}

func (server *validatedDocumentServer) ListDocumentVocabulary(w http.ResponseWriter, r *http.Request, params contract.ListDocumentVocabularyParams) {
	if !validVocabularyQuery(r) {
		transport.WriteError(w, http.StatusBadRequest, "invalid_request", "vocabulary query parameters must be known, unique and valid")
		return
	}
	server.ServerInterface.ListDocumentVocabulary(w, r, params)
}
