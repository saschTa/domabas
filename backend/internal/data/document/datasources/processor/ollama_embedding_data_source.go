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

type OllamaEmbeddingDataSource struct {
	base   string
	client *http.Client
}

func NewOllamaEmbeddingDataSource(base string) (*OllamaEmbeddingDataSource, error) {
	base, err := validURL(base)
	if err != nil {
		return nil, err
	}
	client := privateClient()
	return &OllamaEmbeddingDataSource{base: base, client: client}, nil
}
func (o *OllamaEmbeddingDataSource) Close() { o.client.CloseIdleConnections() }
func (o *OllamaEmbeddingDataSource) wait(ctx context.Context) error {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for attempt := 0; attempt < 60; attempt++ {
		probe, cancel := context.WithTimeout(ctx, 2*time.Second)
		data, status, err := requestJSON(probe, o.client, http.MethodGet, o.base+"/api/version", nil, 4096)
		cancel()
		if err == nil && status == http.StatusOK {
			var version struct {
				Version string `json:"version"`
			}
			if json.Unmarshal(data, &version) == nil && version.Version == "0.34.1" {
				return nil
			}
			return errors.New("unexpected Ollama version")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
	return errors.New("Ollama startup unavailable")
}
func (o *OllamaEmbeddingDataSource) pull(ctx context.Context) error {
	_, status, err := requestJSON(ctx, o.client, http.MethodPost, o.base+"/api/pull", map[string]any{"model": ModelName, "stream": false}, 64<<10)
	if err != nil || status != http.StatusOK {
		return errors.New("pinned embedding pull failed")
	}
	return nil
}
func (o *OllamaEmbeddingDataSource) Ready(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	data, status, err := requestJSON(ctx, o.client, http.MethodGet, o.base+"/api/tags", nil, 128<<10)
	if err != nil || status != http.StatusOK {
		return records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	var tags documentProcessorOllamaTags
	if json.Unmarshal(data, &tags) != nil {
		return records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	for _, model := range tags.Models {
		if model.Name == ModelName || model.Model == ModelName {
			if model.Digest == ModelDigest {
				return nil
			}
			break
		}
	}
	return records.DocumentProcessorError{Code: "inference_unavailable"}
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
func (o *OllamaEmbeddingDataSource) Embed(ctx context.Context, space records.DocumentEmbeddingSpaceRecord, purpose string, inputs []string) (records.DocumentEmbeddingResult, error) {
	if space != installedEmbeddingSpace() {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "configuration_unavailable"}
	}
	if err := validateInputs(purpose, inputs); err != nil {
		return records.DocumentEmbeddingResult{}, err
	}
	if err := o.Ready(ctx); err != nil {
		return records.DocumentEmbeddingResult{}, err
	}
	prefixed := make([]string, len(inputs))
	for i, input := range inputs {
		prefixed[i] = "search_" + purpose + ": " + input
	}
	data, status, err := requestJSON(ctx, o.client, http.MethodPost, o.base+"/api/embed", documentProcessorOllamaEmbedRequest{Model: ModelName, Input: prefixed, Truncate: false, KeepAlive: "10m"}, 1<<20)
	if err != nil {
		if ctx.Err() != nil {
			return records.DocumentEmbeddingResult{}, ctx.Err()
		}
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if status == http.StatusTooManyRequests || status == http.StatusServiceUnavailable {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "overloaded"}
	}
	var response documentProcessorOllamaEmbedResponse
	if json.Unmarshal(data, &response) != nil {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if status != http.StatusOK {
		message := strings.ToLower(response.Error)
		if status == http.StatusBadRequest && (strings.Contains(message, "context length") || strings.Contains(message, "input length")) {
			return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "context_length"}
		}
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if response.Model != ModelName {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "processing_failed"}
	}
	vectors, err := normalizedVectors(response.Embeddings, len(inputs))
	return records.DocumentEmbeddingResult{Space: space, Model: ModelName, Digest: ModelDigest, Vectors: vectors}, err
}

func installedEmbeddingSpace() records.DocumentEmbeddingSpaceRecord {
	return records.DocumentEmbeddingSpaceRecord{Model: ModelName, Digest: ModelDigest, Dimensions: Dimensions, EmbeddingInputRevision: EmbeddingInputRevision, IndexingRevision: IndexingRevision}
}
