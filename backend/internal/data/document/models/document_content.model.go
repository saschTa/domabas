package models

import "time"

type DocumentContentReference struct {
	AccountID, UploaderID, DocumentID, Location string
	OriginalFilename, MediaType, SHA256         string
	Size                                        int64
	IngestedAt                                  time.Time
}

type DocumentProcessorOptions struct{ Language, Segmentation, ExtractionRevision string }
type DocumentProcessorWeight struct {
	Name   string `json:"name"`
	SHA256 string `json:"sha256"`
}
type DocumentExtractionResult struct {
	InvoiceFailureCode string                    `json:"invoiceFailureCode,omitempty"`
	InvoiceXML         []byte                    `json:"invoiceXml,omitempty"`
	ExtractionRevision string                    `json:"extractionRevision"`
	Text               string                    `json:"text"`
	Pages              int                       `json:"pages"`
	Engine             string                    `json:"engine"`
	EngineVersion      string                    `json:"engineVersion"`
	Weights            []DocumentProcessorWeight `json:"weights"`
}
type DocumentEmbeddingResult struct {
	Space   DocumentEmbeddingSpaceRecord `json:"space"`
	Model   string                       `json:"model"`
	Digest  string                       `json:"digest"`
	Vectors [][]float64                  `json:"vectors"`
}
type DocumentProcessorError struct {
	Code string `json:"code"`
}

func (err DocumentProcessorError) Error() string { return err.Code }

type DocumentEmbeddingSpaceRecord struct {
	Model                  string `json:"model"`
	Digest                 string `json:"digest"`
	Dimensions             int    `json:"dimensions"`
	EmbeddingInputRevision string `json:"embeddingInputRevision"`
	IndexingRevision       string `json:"indexingRevision"`
}
