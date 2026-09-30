package repos

import (
	"context"
	"fmt"
	"io"
	"math"
	"strings"

	r "github.com/domabas/domabas/backend/internal/data/paperless/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type PaperlessSource interface {
	Page(context.Context, m.PaperlessConnection, int) (r.PaperlessPageRecord, error)
	Document(context.Context, m.PaperlessConnection, int64) (r.PaperlessDocumentRecord, error)
	Name(context.Context, m.PaperlessConnection, string, int64) (string, error)
	Download(context.Context, m.PaperlessConnection, int64) (io.ReadCloser, error)
}
type PaperlessRepository struct{ source PaperlessSource }

func NewPaperlessRepository(source PaperlessSource) *PaperlessRepository {
	return &PaperlessRepository{source: source}
}
func (r *PaperlessRepository) Preview(ctx context.Context, c m.PaperlessConnection, page int) (m.PaperlessPage, error) {
	v, err := r.source.Page(ctx, c, page)
	if err != nil {
		return m.PaperlessPage{}, err
	}
	if v.Count == nil || *v.Count < 0 || *v.Count > math.MaxInt32 || v.Results == nil || len(v.Results) > m.PageSize {
		return m.PaperlessPage{}, m.PaperlessFailure{Code: "source_incompatible"}
	}
	result := m.PaperlessPage{Total: *v.Count, HasMore: v.Next != nil, Items: []m.PaperlessDocument{}}
	var previous int64
	for _, item := range v.Results {
		if item.ID <= previous || item.ID > 2147483647 {
			return m.PaperlessPage{}, m.PaperlessFailure{Code: "source_incompatible"}
		}
		previous = item.ID
		result.Items = append(result.Items, paperlessPreviewDocumentMapper(item))
	}
	if result.HasMore && len(result.Items) == 0 {
		return m.PaperlessPage{}, m.PaperlessFailure{Code: "source_incompatible"}
	}
	return result, nil
}
func (r *PaperlessRepository) Original(ctx context.Context, c m.PaperlessConnection, id int64) (m.PaperlessOriginal, error) {
	v, err := r.source.Document(ctx, c, id)
	if err != nil {
		return m.PaperlessOriginal{}, err
	}
	if v.ID != id {
		return m.PaperlessOriginal{}, m.PaperlessFailure{Code: "invalid_metadata"}
	}
	metadata, err := r.metadataMapper(ctx, c, v)
	if err != nil {
		return m.PaperlessOriginal{}, err
	}
	filename := v.Filename
	if strings.TrimSpace(filename) == "" {
		filename = fmt.Sprintf("paperless-%d", id)
	}
	reader, err := r.source.Download(ctx, c, id)
	if err != nil {
		return m.PaperlessOriginal{}, err
	}
	return m.PaperlessOriginal{Metadata: metadata, Filename: filename, Reader: reader}, nil
}
