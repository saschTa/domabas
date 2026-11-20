package processor

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
)

type LlamaEmbeddingDataSource struct {
	base   string
	client *http.Client
}

func NewLlamaEmbeddingDataSource(base string) (*LlamaEmbeddingDataSource, error) {
	base, err := validURL(base)
	if err != nil {
		return nil, err
	}
	client := privateClient()
	return &LlamaEmbeddingDataSource{base: base, client: client}, nil
}
func (l *LlamaEmbeddingDataSource) Close() { l.client.CloseIdleConnections() }
func (l *LlamaEmbeddingDataSource) wait(ctx context.Context) error {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for attempt := 0; attempt < 60; attempt++ {
		if l.Ready(ctx) == nil {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
	return errors.New("llama.cpp embedding server unavailable")
}
func (l *LlamaEmbeddingDataSource) Ready(ctx context.Context) error {
	probe, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	data, status, err := requestJSON(probe, l.client, http.MethodGet, l.base+"/v1/models", nil, 128<<10)
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err != nil || status != http.StatusOK {
		return records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	var models struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if json.Unmarshal(data, &models) != nil || len(models.Data) != 1 || models.Data[0].ID != ModelName {
		return records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	return nil
}
func validateInputs(purpose string, inputs []string) error {
	if (purpose != "query" && purpose != "document") || len(inputs) < 1 || len(inputs) > 8 {
		return records.DocumentProcessorError{Code: "resource_limit"}
	}
	for _, input := range inputs {
		if !utf8.ValidString(input) || strings.TrimSpace(input) == "" || len(input) > 8192 {
			return records.DocumentProcessorError{Code: "resource_limit"}
		}
	}
	return nil
}
func normalizedVectors(vectors [][]float64, count int) ([][]float64, error) {
	if len(vectors) != count {
		return nil, records.DocumentProcessorError{Code: "processing_failed"}
	}
	result := make([][]float64, len(vectors))
	for i, vector := range vectors {
		if len(vector) != Dimensions {
			return nil, records.DocumentProcessorError{Code: "processing_failed"}
		}
		norm := 0.0
		for _, v := range vector {
			if math.IsNaN(v) || math.IsInf(v, 0) {
				return nil, records.DocumentProcessorError{Code: "processing_failed"}
			}
			norm += v * v
		}
		if norm <= 0 || math.IsNaN(norm) || math.IsInf(norm, 0) {
			return nil, records.DocumentProcessorError{Code: "processing_failed"}
		}
		norm = math.Sqrt(norm)
		result[i] = make([]float64, len(vector))
		for j, v := range vector {
			result[i][j] = v / norm
		}
	}
	return result, nil
}
func (l *LlamaEmbeddingDataSource) Embed(ctx context.Context, space records.DocumentEmbeddingSpaceRecord, purpose string, inputs []string) (records.DocumentEmbeddingResult, error) {
	if space != installedEmbeddingSpace() {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "configuration_unavailable"}
	}
	if err := validateInputs(purpose, inputs); err != nil {
		return records.DocumentEmbeddingResult{}, err
	}
	if err := l.Ready(ctx); err != nil {
		return records.DocumentEmbeddingResult{}, err
	}
	prefixed := make([]string, len(inputs))
	for i, input := range inputs {
		prefixed[i] = "search_" + purpose + ": " + input
	}
	data, status, err := requestJSON(ctx, l.client, http.MethodPost, l.base+"/v1/embeddings", documentProcessorLlamaEmbedRequest{Model: ModelName, Input: prefixed, EncodingFormat: "float"}, 1<<20)
	if err != nil {
		if ctx.Err() != nil {
			return records.DocumentEmbeddingResult{}, ctx.Err()
		}
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if status == http.StatusTooManyRequests || status == http.StatusServiceUnavailable {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "overloaded"}
	}
	var response documentProcessorLlamaEmbedResponse
	if json.Unmarshal(data, &response) != nil {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if status != http.StatusOK {
		if response.Error.Type == "exceed_context_size_error" || (status == http.StatusInternalServerError && strings.Contains(response.Error.Message, "increase the physical batch size")) {
			return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "context_length"}
		}
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if response.Model != ModelName || len(response.Data) != len(inputs) {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "processing_failed"}
	}
	ordered := make([][]float64, len(inputs))
	for _, item := range response.Data {
		if item.Index == nil || *item.Index < 0 || *item.Index >= len(ordered) || item.Embedding == nil || ordered[*item.Index] != nil {
			return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "processing_failed"}
		}
		ordered[*item.Index] = item.Embedding
	}
	vectors, err := normalizedVectors(ordered, len(inputs))
	return records.DocumentEmbeddingResult{Space: space, Model: ModelName, Digest: ModelDigest, Vectors: vectors}, err
}

func installedEmbeddingSpace() records.DocumentEmbeddingSpaceRecord {
	return records.DocumentEmbeddingSpaceRecord{Model: ModelName, Digest: ModelDigest, Dimensions: Dimensions, EmbeddingInputRevision: EmbeddingInputRevision, IndexingRevision: IndexingRevision}
}
