package repos

import (
	"context"
	"errors"
	"io"
	"strings"
	"unicode/utf8"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentEmailInspectionSource interface {
	Inspect(context.Context, io.Reader, func(r.DocumentEmailPart) error) (r.DocumentEmailInspection, error)
	Envelope(io.Reader) (r.DocumentEmailMetadata, error)
}
type DocumentEmailInspectionRepository struct{ source DocumentEmailInspectionSource }

func NewDocumentEmailInspectionRepository(source DocumentEmailInspectionSource) *DocumentEmailInspectionRepository {
	return &DocumentEmailInspectionRepository{source: source}
}
func boundedEmailText(value string, characters, bytes int) string {
	value = strings.TrimSpace(value)
	runes := []rune(value)
	if len(runes) > characters {
		value = string(runes[:characters])
	}
	for len(value) > bytes {
		_, n := utf8.DecodeLastRuneInString(value)
		value = value[:len(value)-n]
	}
	return value
}
func (s *DocumentEmailInspectionRepository) Inspect(ctx context.Context, reader io.Reader, visit func(m.DocumentEmailPart) error) (m.DocumentEmailInspection, error) {
	var visitorError error
	result, err := s.source.Inspect(ctx, reader, func(part r.DocumentEmailPart) error {
		visitorError = visit(m.DocumentEmailPart(part))
		return visitorError
	})
	if err != nil && ctx.Err() == nil && (visitorError == nil || !errors.Is(err, visitorError)) {
		err = m.DocumentProcessingError{Code: "invalid_email"}
	}
	metadata := documentEmailMetadataMapper(result.Metadata)
	return m.DocumentEmailInspection{Metadata: metadata, ContentFailures: result.ContentFailures}, err
}

func (s *DocumentEmailInspectionRepository) Envelope(reader io.Reader) (m.DocumentMetadata, error) {
	result, err := s.source.Envelope(reader)
	return documentEmailMetadataMapper(result), err
}
