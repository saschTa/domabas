package models

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

const InstalledPipelineManifestRevision int64 = 2
const CurrentExtractionRevision = "document-content-v2"
const LegacyExtractionRevision = "tesseract-pdf-image-v1"
const LegacyChunkingRevision = "ocr-rune-chunks-v1"
const LegacyEmbeddingInputRevision = "nomic-search-prefix-v1"
const LegacyIndexingRevision = "normalized-cosine-v1"

func (c DocumentProcessingConfiguration) EmbeddingSpace() DocumentEmbeddingSpace {
	return DocumentEmbeddingSpace{c.EmbeddingModel, c.EmbeddingDigest, c.Dimensions, c.EmbeddingInputRevision, c.IndexingRevision}
}
func (c DocumentProcessingConfiguration) WithLegacyIdentity() DocumentProcessingConfiguration {
	if c.ManifestRevision == 0 {
		c.ManifestRevision = 1
	}
	if c.ExtractionRevision == "" {
		c.ExtractionRevision = LegacyExtractionRevision
	}
	if c.ChunkingRevision == "" {
		c.ChunkingRevision = LegacyChunkingRevision
	}
	if c.EmbeddingInputRevision == "" {
		c.EmbeddingInputRevision = LegacyEmbeddingInputRevision
	}
	if c.IndexingRevision == "" {
		c.IndexingRevision = LegacyIndexingRevision
	}
	c.Fingerprint, _ = c.CanonicalFingerprint()
	return c
}
func (c DocumentProcessingConfiguration) CanonicalFingerprint() (string, error) {
	if err := c.Validate(); err != nil {
		return "", err
	}
	weights := append([]DocumentWeight{}, c.Weights...)
	sort.Slice(weights, func(i, j int) bool { return weights[i].Name < weights[j].Name })
	if len(weights) > 16 {
		return "", DocumentValidationError{"too many OCR weights"}
	}
	for i, w := range weights {
		if w.Name == "" || len(w.Name) > 64 || !validDigest(w.SHA256) || (i > 0 && weights[i-1].Name == w.Name) {
			return "", DocumentValidationError{"invalid OCR weight identity"}
		}
	}
	if !validDigest(c.EmbeddingDigest) || c.EmbeddingModel == "" || len(c.EmbeddingModel) > 128 || c.Dimensions != EmbeddingDimensions {
		return "", DocumentValidationError{"invalid embedding identity"}
	}
	for _, v := range []string{c.ExtractionRevision, c.ChunkingRevision, c.EmbeddingInputRevision, c.IndexingRevision} {
		if v == "" || len(v) > 64 {
			return "", DocumentValidationError{"invalid pipeline algorithm identity"}
		}
	}
	payload := []string{"1", c.Language, c.Segmentation, c.Engine, c.EngineVersion, c.EmbeddingModel, c.EmbeddingDigest, strconv.Itoa(c.Dimensions), c.ExtractionRevision, c.ChunkingRevision, c.EmbeddingInputRevision, c.IndexingRevision}
	for _, w := range weights {
		payload = append(payload, w.Name, w.SHA256)
	}
	llm := c.LLM.Defaults()
	invoiceEnabled := llm.InvoiceExtractionEnabled()
	llm.InvoiceEnabled = nil
	if err := llm.Validate(); err != nil {
		return "", err
	}
	contextLength := llm.ContextLength
	llm.ContextLength = 0
	compatibility := llm.LMStudioCompatibility
	llm.LMStudioCompatibility = false
	propertyThinking, invoiceThinking := llm.PropertyThinkingEnabled, llm.InvoiceThinkingEnabled
	llm.PropertyThinkingEnabled, llm.InvoiceThinkingEnabled = false, false
	if llm != (DocumentLLMConfiguration{}).Defaults() {
		payload = append(payload, "property-extraction-v1", strconv.FormatBool(llm.Enabled), llm.Provider, llm.Model, llm.BaseURL, llm.CredentialID)
	}
	if invoiceEnabled != llm.Enabled {
		payload = append(payload, "invoice-extraction-v1", strconv.FormatBool(invoiceEnabled))
	}
	if contextLength != 0 {
		payload = append(payload, "model-context-v1", strconv.Itoa(contextLength))
	}
	if compatibility {
		payload = append(payload, "lm-studio-compatibility-v1", "true")
	}
	if propertyThinking {
		payload = append(payload, "property-thinking-v1", "true")
	}
	if invoiceThinking {
		payload = append(payload, "invoice-thinking-v1", "true")
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:]), nil
}
func (c DocumentProcessingConfiguration) ManifestFingerprint() (string, error) {
	c.LLM = DocumentLLMConfiguration{}
	c.Language = "eng+deu"
	c.Segmentation = "auto"
	return c.CanonicalFingerprint()
}
func validDigest(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, r := range value {
		if !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f') {
			return false
		}
	}
	return true
}
func (s DocumentEmbeddingSpace) Supported() bool { return s == DefaultConfiguration().EmbeddingSpace() }

func (c DocumentProcessingConfiguration) ExtractionIdentity(mediaType string) (DocumentExtractionIdentity, error) {
	c = c.WithLegacyIdentity()
	legacy := c.ManifestRevision == 1 && c.ExtractionRevision == LegacyExtractionRevision
	current := c.ManifestRevision == InstalledPipelineManifestRevision && c.ExtractionRevision == CurrentExtractionRevision
	if !legacy && !current {
		return DocumentExtractionIdentity{}, DocumentProcessingError{Code: "configuration_unavailable"}
	}
	installed := DefaultConfiguration()
	installed.ManifestRevision, installed.ExtractionRevision = c.ManifestRevision, c.ExtractionRevision
	expected, err := installed.ManifestFingerprint()
	actual, identityErr := c.ManifestFingerprint()
	if err != nil || identityErr != nil || actual != expected {
		return DocumentExtractionIdentity{}, DocumentProcessingError{Code: "configuration_unavailable"}
	}
	switch mediaType {
	case "message/rfc822":
		if !current {
			return DocumentExtractionIdentity{}, DocumentProcessingError{Code: "configuration_unavailable"}
		}
		return DocumentExtractionIdentity{Method: "mime", Engine: "domabas-mime", EngineVersion: "1", Weights: []DocumentWeight{}}, nil
	case "application/pdf", "image/png", "image/jpeg":
		return DocumentExtractionIdentity{Method: "ocr", Engine: c.Engine, EngineVersion: c.EngineVersion, Weights: append([]DocumentWeight{}, c.Weights...)}, nil
	default:
		return DocumentExtractionIdentity{}, DocumentProcessingError{Code: "invalid_file"}
	}
}

func (c DocumentProcessingConfiguration) ValidateExtraction(mediaType string, result DocumentExtraction) error {
	identity, err := c.ExtractionIdentity(mediaType)
	if err != nil {
		return err
	}
	if (result.InvoiceFailureCode != "" && (result.InvoiceFailureCode != "invalid_invoice" || mediaType != "application/pdf")) || len(result.InvoiceXML) > 2<<20 || (len(result.InvoiceXML) > 0 && mediaType != "application/pdf") || len(result.Text) > MaxOCRBytes || !utf8.ValidString(result.Text) || strings.ContainsRune(result.Text, 0) || result.Pages < 1 || result.Pages > MaxPDFPages || result.ExtractionRevision != c.WithLegacyIdentity().ExtractionRevision || result.Engine != identity.Engine || result.EngineVersion != identity.EngineVersion || len(result.Weights) != len(identity.Weights) {
		return DocumentProcessingError{Code: "processing_failed"}
	}
	if identity.Method == "mime" && result.Pages != 1 {
		return DocumentProcessingError{Code: "processing_failed"}
	}
	expected := make(map[string]string, len(identity.Weights))
	for _, weight := range identity.Weights {
		expected[weight.Name] = weight.SHA256
	}
	for _, weight := range result.Weights {
		if digest, exists := expected[weight.Name]; !exists || digest != weight.SHA256 {
			return DocumentProcessingError{Code: "processing_failed"}
		}
		delete(expected, weight.Name)
	}
	return nil
}
