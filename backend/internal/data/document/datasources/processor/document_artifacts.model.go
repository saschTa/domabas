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
type documentProcessorOllamaEmbedRequest struct {
	Model     string   `json:"model"`
	Input     []string `json:"input"`
	Truncate  bool     `json:"truncate"`
	KeepAlive string   `json:"keep_alive"`
}
type documentProcessorOllamaEmbedResponse struct {
	Model      string      `json:"model"`
	Embeddings [][]float64 `json:"embeddings"`
	Error      string      `json:"error"`
}
type documentProcessorOllamaTags struct {
	Models []documentProcessorOllamaModel `json:"models"`
}
type documentProcessorOllamaModel struct {
	Name   string `json:"name"`
	Model  string `json:"model"`
	Digest string `json:"digest"`
}
type documentProcessorCacheManifest struct {
	SchemaVersion int                           `json:"schemaVersion"`
	Config        documentProcessorCacheLayer   `json:"config"`
	Layers        []documentProcessorCacheLayer `json:"layers"`
}
type documentProcessorCacheLayer struct {
	MediaType string `json:"mediaType"`
	Digest    string `json:"digest"`
	Size      int64  `json:"size"`
}
