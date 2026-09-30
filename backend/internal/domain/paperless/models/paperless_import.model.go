package models

import (
	"errors"
	"io"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
)

const PageSize = 100

type PaperlessConnection struct {
	ServerURL, Token    string
	MaximumUnclosedRuns int
}
type PaperlessDocument struct {
	ID    int64
	Title string
}
type PaperlessPage struct {
	Items   []PaperlessDocument
	Total   int
	HasMore bool
}
type PaperlessOriginal struct {
	Metadata document.DocumentMetadata
	Filename string
	Reader   io.ReadCloser
}
type PaperlessResult struct {
	DocumentID string
	Duplicate  bool
}
type PaperlessFailure struct{ Code string }

func (f PaperlessFailure) Error() string { return f.Code }

var ErrBusy = errors.New("paperless importer busy")
