package services

import (
	"context"
	"errors"
	"testing"
	"time"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type searchRepository struct {
	p.DocumentIngestionRepository
	input              m.DocumentSearchInput
	vector             []float64
	configurationCalls int
	searchCalls        int
	failure            error
}

func (r *searchRepository) SearchConfiguration(context.Context, m.DocumentActor) (m.DocumentProcessingConfiguration, error) {
	r.configurationCalls++
	return m.DefaultConfiguration(), r.failure
}

func (r *searchRepository) Search(_ context.Context, _ m.DocumentActor, input m.DocumentSearchInput, vector []float64) (m.DocumentSearchResults, error) {
	r.searchCalls++
	r.input, r.vector = input, vector
	return m.DocumentSearchResults{}, nil
}

func TestHybridSearchEmbedsNonemptyQueriesAndPreservesFailure(t *testing.T) {
	for _, tc := range []struct {
		mode, query string
		embeds      bool
	}{
		{"hybrid", "automobile repair", true},
		{"hybrid", "  ", false},
		{"fulltext", "invoice", false},
		{"semantic", "automobile repair", true},
	} {
		r := &searchRepository{}
		processor := &embeddingProcessor{max: 1000}
		service := NewDocumentIngestionService(r, nil, processor, documentAllowedAuthority(), time.Now)
		if _, err := service.Search(t.Context(), m.DocumentActor{}, m.DocumentSearchInput{Mode: tc.mode, Query: tc.query}); err != nil {
			t.Fatal(err)
		}
		if r.searchCalls != 1 || (processor.calls == 1) != tc.embeds || (r.configurationCalls == 1) != tc.embeds {
			t.Fatalf("wrong search path for %+v: %+v", tc, r)
		}
		if tc.embeds && (r.input.Space != m.DefaultConfiguration().EmbeddingSpace() || len(r.vector) != m.EmbeddingDimensions || r.vector[0] != 1) {
			t.Fatalf("unvalidated query vector: %+v", r)
		}
	}
	for _, permissionFailure := range []bool{false, true} {
		r := &searchRepository{}
		processor := &embeddingProcessor{failure: errors.New("private inference failure")}
		want := m.ErrUnavailable
		if permissionFailure {
			r.failure, want = m.ErrForbidden, m.ErrForbidden
		}
		service := NewDocumentIngestionService(r, nil, processor, documentAllowedAuthority(), time.Now)
		_, err := service.Search(t.Context(), m.DocumentActor{}, m.DocumentSearchInput{Mode: "hybrid", Query: "invoice"})
		if !errors.Is(err, want) || r.searchCalls != 0 || (permissionFailure && processor.calls != 0) {
			t.Fatalf("hybrid downgraded or inferred before authorization: %v %+v", err, r)
		}
	}
}
