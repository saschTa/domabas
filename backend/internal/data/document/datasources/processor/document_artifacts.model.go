package processor

import records "github.com/domabas/domabas/backend/internal/data/document/models"

type documentProcessorArtifact struct {
	Name   string
	Size   int64
	SHA256 string
}
type documentProcessorEmbedRequest struct {
	Space   records.DocumentEmbeddingSpaceRecord `json:"space"`
	Purpose string                               `json:"purpose"`
	Inputs  []string                             `json:"inputs"`
}
type documentProcessorLlamaEmbedRequest struct {
	Model          string   `json:"model"`
	Input          []string `json:"input"`
	EncodingFormat string   `json:"encoding_format"`
}
type documentProcessorLlamaEmbedResponse struct {
	Model string `json:"model"`
	Data  []struct {
		Index     *int      `json:"index"`
		Embedding []float64 `json:"embedding"`
	} `json:"data"`
	Error struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error"`
}
