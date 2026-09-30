package processor

type documentProcessorEmbeddingSpace struct {
	Model                  string `json:"model"`
	Digest                 string `json:"digest"`
	Dimensions             int    `json:"dimensions"`
	EmbeddingInputRevision string `json:"embeddingInputRevision"`
	IndexingRevision       string `json:"indexingRevision"`
}
type documentProcessorEmbedRequest struct {
	Space   documentProcessorEmbeddingSpace `json:"space"`
	Purpose string                          `json:"purpose"`
	Inputs  []string                        `json:"inputs"`
}
type documentProcessorErrorResponse struct {
	Code string `json:"code"`
}
type documentProcessorWeightResponse struct {
	Name   string `json:"name"`
	SHA256 string `json:"sha256"`
}
type documentProcessorExtractionResponse struct {
	InvoiceXML         []byte                            `json:"invoiceXml,omitempty"`
	ExtractionRevision string                            `json:"extractionRevision"`
	Text               string                            `json:"text"`
	Pages              int                               `json:"pages"`
	Engine             string                            `json:"engine"`
	EngineVersion      string                            `json:"engineVersion"`
	Weights            []documentProcessorWeightResponse `json:"weights"`
}
type documentProcessorEmbeddingResponse struct {
	Space   documentProcessorEmbeddingSpace `json:"space"`
	Model   string                          `json:"model"`
	Digest  string                          `json:"digest"`
	Vectors [][]float64                     `json:"vectors"`
}
