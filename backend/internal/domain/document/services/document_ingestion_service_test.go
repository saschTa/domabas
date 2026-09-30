package services

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type embeddingRepository struct {
	p.DocumentIngestionRepository
	chunks []m.DocumentChunk
	saved  []m.DocumentChunk
}

func (r *embeddingRepository) Work(context.Context, m.DocumentJob, string) (m.DocumentProcessingWork, error) {
	return m.DocumentProcessingWork{Eligible: true, State: "processing", Configuration: m.DefaultConfiguration(), Stage: "embedding", Chunks: r.chunks}, nil
}
func (r *embeddingRepository) BeginWork(context.Context, m.DocumentProcessingCommand) error {
	return nil
}
func (r *embeddingRepository) SaveEmbeddings(_ context.Context, c m.DocumentEmbeddingCommand) error {
	r.saved = c.Chunks
	return nil
}

type embeddingProcessor struct {
	p.DocumentProcessor
	max     int
	calls   int
	failure error
}

func (p *embeddingProcessor) Embed(_ context.Context, space m.DocumentEmbeddingSpace, _ string, values []string) (m.DocumentEmbedding, error) {
	p.calls++
	if p.failure != nil {
		return m.DocumentEmbedding{}, p.failure
	}
	result := m.DocumentEmbedding{Space: space, Model: space.Model, Digest: space.Digest}
	for _, value := range values {
		if len([]rune(value)) > p.max {
			return m.DocumentEmbedding{}, m.ErrEmbeddingContextLength
		}
		v := make([]float64, m.EmbeddingDimensions)
		v[0] = 2
		result.Vectors = append(result.Vectors, v)
	}
	return result, nil
}
func TestEmbeddingContextRejectionSplitsOnlyRejectedChunks(t *testing.T) {
	repository := &embeddingRepository{chunks: []m.DocumentChunk{{Text: strings.Repeat("a", 20)}, {Text: "small"}}}
	processor := &embeddingProcessor{max: 10}
	service := NewDocumentIngestionService(repository, nil, processor, documentAllowedAuthority(), time.Now)
	if err := service.Embed(t.Context(), m.DocumentJob{}); err != nil {
		t.Fatal(err)
	}
	if len(repository.saved) != 3 || repository.saved[0].Text != strings.Repeat("a", 10) || repository.saved[1].Text != strings.Repeat("a", 10) || repository.saved[2].Text != "small" {
		t.Fatalf("split changed content: %+v", repository.saved)
	}
	for i, chunk := range repository.saved {
		if chunk.Position != i || chunk.Vector[0] != 1 {
			t.Fatalf("invalid persisted vector/position: %+v", chunk)
		}
	}
	processor.failure = errors.New("private inference server error")
	repository.saved = nil
	before := processor.calls
	err := service.Embed(t.Context(), m.DocumentJob{})
	var typed m.DocumentProcessingError
	if !errors.As(err, &typed) || typed.Code != "processing_failed" || processor.calls != before+1 || repository.saved != nil {
		t.Fatalf("non-context failure triggered splitting/publication: %v", err)
	}
}
func TestChunkingBoundsOverlapAndEmptyText(t *testing.T) {
	text := strings.Repeat("Unicode 世界 and invoices. ", 400)
	chunks, err := ChunkText(text)
	if err != nil || len(chunks) < 2 {
		t.Fatalf("chunking: %d %v", len(chunks), err)
	}
	for i, c := range chunks {
		if c.Position != i || len([]rune(c.Text)) > 2048 || len(c.Text) > 8192 || c.Text == "" {
			t.Fatalf("invalid chunk %d", i)
		}
	}
	again, err := ChunkText(text)
	if err != nil || len(again) != len(chunks) {
		t.Fatal("nondeterministic chunking")
	}
	for i := range chunks {
		if chunks[i].Text != again[i].Text {
			t.Fatal("nondeterministic chunk values")
		}
	}
	for _, value := range []string{strings.Repeat("a", m.MaxOCRBytes+1), strings.Repeat("世", m.MaxOCRBytes/3+1)} {
		if _, err = ChunkText(value); err == nil {
			t.Fatal("oversized text accepted")
		}
	}
	if empty, err := ChunkText(" \n\t "); err != nil || len(empty) != 0 {
		t.Fatalf("empty text must need no chunks: %v", err)
	}
}

func TestProcessorOverloadRemainsDistinctForDurableRetry(t *testing.T) {
	repository := &embeddingRepository{chunks: []m.DocumentChunk{{Text: "A complete document chunk"}}}
	processor := &embeddingProcessor{failure: errors.Join(errors.New("private processor address"), m.ErrOverloaded)}
	service := NewDocumentIngestionService(repository, nil, processor, documentAllowedAuthority(), time.Now)
	if err := service.Embed(t.Context(), m.DocumentJob{}); !errors.Is(err, m.ErrOverloaded) || processor.calls != 1 || repository.saved != nil {
		t.Fatalf("busy processor lost its retry classification or published partial results: %v", err)
	}
}
