package models

import (
	"errors"
	"math"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

const EmbeddingDigest = "0a109f422b47e3a30ba2b10eca18548e944e8a23073ee3f3e947efcf3c45e59f"
const EmbeddingDimensions = 768
const MaxFileBytes int64 = 100 << 20
const MaxPDFPages = 200

var (
	ErrStaleJob               = errors.New("stale document processing job")
	ErrDuplicate              = errors.New("duplicate document")
	ErrConflict               = errors.New("document state conflict")
	ErrUnauthorized           = errors.New("document authority is no longer valid")
	ErrForbidden              = errors.New("document permission denied")
	ErrInvalidPDFPassword     = errors.New("incorrect PDF password")
	ErrPasswordChangeRequired = errors.New("password change required")
	ErrUnavailable            = errors.New("document dependency unavailable")
	ErrTooLarge               = errors.New("document limit exceeded")
	ErrUnsupportedMedia       = errors.New("unsupported document media")
	ErrOverloaded             = errors.New("document processing overloaded")
	ErrEmbeddingContextLength = errors.New("embedding context length exceeded")
)

func (e DocumentProcessingError) Error() string { return e.Code }
func ValidFailureCode(code string) bool {
	switch code {
	case "invalid_invoice", "invalid_classification", "output_limit", "empty_response", "response_too_large", "configuration_unavailable", "no_text", "invalid_file", "encrypted_pdf", "resource_limit", "processing_failed", "processing_timeout", "delivery_timeout", "processing_incomplete", "processing_cancelled", "processing_terminated", "inference_unavailable", "storage_unavailable":
		return true
	}
	return false
}
func DefaultConfiguration() DocumentProcessingConfiguration {
	c := DocumentProcessingConfiguration{ManifestRevision: InstalledPipelineManifestRevision, ExtractionRevision: CurrentExtractionRevision, ChunkingRevision: LegacyChunkingRevision, EmbeddingInputRevision: LegacyEmbeddingInputRevision, IndexingRevision: LegacyIndexingRevision, Revision: 1, Language: "eng+deu", Segmentation: "auto", Engine: "tesseract", EngineVersion: "5.5.3", EmbeddingModel: "nomic-embed-text:v1.5", EmbeddingDigest: EmbeddingDigest, Dimensions: EmbeddingDimensions, Weights: []DocumentWeight{{"eng", "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2"}, {"deu", "19d219bbb6672c869d20a9636c6816a81eb9a71796cb93ebe0cb1530e2cdb22d"}, {"osd", "9cf5d576fcc47564f11265841e5ca839001e7e6f38ff7f7aacf46d15a96b00ff"}}}
	c.LLM = DocumentLLMConfiguration{Model: "qwen3.5:4b", ContextLength: DefaultDocumentContextLength}
	c.Fingerprint, _ = c.CanonicalFingerprint()
	return c
}
func (c DocumentProcessingConfiguration) Validate() error {
	if c.Language != "eng" && c.Language != "deu" && c.Language != "eng+deu" {
		return DocumentValidationError{"unsupported OCR language"}
	}
	if c.Segmentation != "auto" && c.Segmentation != "single_block" {
		return DocumentValidationError{"unsupported OCR segmentation"}
	}
	return nil
}
func validText(s string, runes, bytes int, controls bool) bool {
	if !utf8.ValidString(s) || utf8.RuneCountInString(s) > runes || len(s) > bytes {
		return false
	}
	for _, r := range s {
		if r == 0 || (!controls && unicode.IsControl(r)) {
			return false
		}
	}
	return true
}
func NormalizeTags(values []string) ([]string, error) {
	if len(values) > 20 {
		return nil, DocumentValidationError{"at most 20 tags are allowed"}
	}
	result := make([]string, 0, len(values))
	seen := map[string]bool{}
	for _, v := range values {
		v = strings.ToLower(strings.TrimSpace(v))
		if v == "" || !validText(v, 64, 256, false) || seen[v] {
			return nil, DocumentValidationError{"tags must be unique bounded display strings"}
		}
		seen[v] = true
		result = append(result, v)
	}
	sort.Strings(result)
	return result, nil
}
func normalizeAddresses(values []string) ([]string, error) {
	if len(values) > 20 {
		return nil, DocumentValidationError{"at most 20 recipients are allowed"}
	}
	result := make([]string, 0, len(values))
	seen := map[string]bool{}
	for _, v := range values {
		v = strings.TrimSpace(v)
		if v == "" || !validText(v, 320, 1280, false) || seen[v] {
			return nil, DocumentValidationError{"recipients must be unique bounded display strings"}
		}
		seen[v] = true
		result = append(result, v)
	}
	return result, nil
}
func (m DocumentMetadata) Normalize() (DocumentMetadata, error) {
	if !validText(m.Title, 200, 800, false) || strings.TrimSpace(m.Title) == "" {
		return m, DocumentValidationError{"title must contain 1 to 200 display characters"}
	}
	m.Title = strings.TrimSpace(m.Title)
	if !validText(m.Description, 4000, 16000, true) {
		return m, DocumentValidationError{"description is too long or invalid"}
	}
	if m.Kind == "" {
		m.Kind = "document"
	}
	if m.Kind != "document" && m.Kind != "letter" && m.Kind != "email" {
		return m, DocumentValidationError{"invalid document kind"}
	}
	var err error
	if m.Tags, err = NormalizeTags(m.Tags); err != nil {
		return m, err
	}
	if m.Recipients, err = normalizeAddresses(m.Recipients); err != nil {
		return m, err
	}
	if m.CC, err = normalizeAddresses(m.CC); err != nil {
		return m, err
	}
	if m.BCC, err = normalizeAddresses(m.BCC); err != nil {
		return m, err
	}
	m.Sender = strings.TrimSpace(m.Sender)
	m.Subject = strings.TrimSpace(m.Subject)
	m.MessageID = strings.TrimSpace(m.MessageID)
	if !validText(m.Sender, 320, 1280, false) || !validText(m.Subject, 200, 800, false) || !validText(m.MessageID, 512, 2048, false) {
		return m, DocumentValidationError{"invalid document display field"}
	}
	if m.DocumentDate != "" {
		parsed, e := time.Parse("2006-01-02", m.DocumentDate)
		if e != nil || parsed.Format("2006-01-02") != m.DocumentDate || parsed.Year() < 1 {
			return m, DocumentValidationError{"invalid document date"}
		}
	}
	return m, nil
}
func (p DocumentMetadataPatch) Apply(m DocumentMetadata) (DocumentMetadata, error) {
	if p.Title == nil && p.Description == nil && p.Kind == nil && p.Sender == nil && p.DocumentDate == nil && p.Subject == nil && p.MessageID == nil && p.Tags == nil && p.Recipients == nil && p.CC == nil && p.BCC == nil {
		return m, DocumentValidationError{"metadata patch must contain a field"}
	}
	if p.Title != nil {
		m.Title = *p.Title
	}
	if p.Description != nil {
		m.Description = *p.Description
	}
	if p.Kind != nil {
		if *p.Kind == "" {
			return m, DocumentValidationError{"invalid document kind"}
		}
		m.Kind = *p.Kind
	}
	if p.Sender != nil {
		m.Sender = *p.Sender
	}
	if p.DocumentDate != nil {
		m.DocumentDate = *p.DocumentDate
	}
	if p.Subject != nil {
		m.Subject = *p.Subject
	}
	if p.MessageID != nil {
		m.MessageID = *p.MessageID
	}
	if p.Tags != nil {
		m.Tags = *p.Tags
	}
	if p.Recipients != nil {
		m.Recipients = *p.Recipients
	}
	if p.CC != nil {
		m.CC = *p.CC
	}
	if p.BCC != nil {
		m.BCC = *p.BCC
	}
	return m.Normalize()
}
func (s DocumentSearchInput) Normalize() (DocumentSearchInput, error) {
	if len(s.Kinds) > 3 {
		return s, DocumentValidationError{"invalid document kinds"}
	}
	kinds := make(map[string]bool, len(s.Kinds))
	for _, kind := range s.Kinds {
		if kind != "document" && kind != "letter" && kind != "email" {
			return s, DocumentValidationError{"invalid document kind"}
		}
		kinds[kind] = true
	}
	s.Kinds = []string{}
	if len(kinds) < 3 {
		for kind := range kinds {
			s.Kinds = append(s.Kinds, kind)
		}
		sort.Strings(s.Kinds)
	}
	for _, mode := range []string{s.SenderMatch, s.RecipientMatch} {
		if mode != "" && mode != "contains" && mode != "exact" {
			return s, DocumentValidationError{"invalid address matching mode"}
		}
	}
	s.Query = strings.TrimSpace(s.Query)
	if !validText(s.Query, 1000, 4096, true) || (s.Mode != "fulltext" && s.Mode != "semantic" && s.Mode != "hybrid") || (s.Query == "" && s.Mode == "semantic") {
		return s, DocumentValidationError{"invalid search query or mode"}
	}
	if s.Limit == 0 {
		s.Limit = 20
	}
	if s.Limit < 1 || s.Limit > 50 || s.Offset < 0 || s.Offset > 10000 {
		return s, DocumentValidationError{"invalid search pagination"}
	}
	if len(s.Cursor) > 4096 || (s.Cursor != "" && s.Offset != 0) {
		return s, DocumentValidationError{"invalid search cursor or pagination"}
	}
	s.Sender = strings.TrimSpace(s.Sender)
	s.Recipient = strings.TrimSpace(s.Recipient)
	if !validText(s.Sender, 320, 1280, false) || !validText(s.Recipient, 320, 1280, false) {
		return s, DocumentValidationError{"invalid sender or recipient filter"}
	}
	if s.SenderMatch == "" || s.Sender == "" {
		s.SenderMatch = "contains"
	}
	if s.RecipientMatch == "" || s.Recipient == "" {
		s.RecipientMatch = "contains"
	}
	if s.Sort == "" {
		s.Sort = "relevance"
		if s.Query == "" {
			s.Sort = "newest"
		}
	}
	switch s.Sort {
	case "relevance":
		if s.Query == "" {
			return s, DocumentValidationError{"relevance requires a search term"}
		}
	case "newest", "oldest", "title", "date-newest", "date-oldest":
	default:
		return s, DocumentValidationError{"invalid search sort"}
	}
	var err error
	s.Tags, err = NormalizeTags(s.Tags)
	return s, err
}
func (s DocumentSearchInput) UsesEmbeddings() bool {
	return s.Mode == "semantic" || (s.Mode == "hybrid" && s.Query != "")
}
func NormalizeVector(vector []float64) ([]float64, error) {
	if len(vector) != EmbeddingDimensions {
		return nil, DocumentProcessingError{"processing_failed", false}
	}
	norm := 0.0
	for _, v := range vector {
		if math.IsNaN(v) || math.IsInf(v, 0) {
			return nil, DocumentProcessingError{"processing_failed", false}
		}
		norm += v * v
	}
	if norm <= 0 || math.IsInf(norm, 0) {
		return nil, DocumentProcessingError{"processing_failed", false}
	}
	norm = math.Sqrt(norm)
	result := make([]float64, len(vector))
	for i, v := range vector {
		result[i] = v / norm
	}
	return result, nil
}
func (d Document) Metadata() DocumentMetadata {
	return DocumentMetadata{Title: d.Title, Description: d.Description, Kind: d.Kind, Tags: d.Tags, Sender: d.Sender, Recipients: d.Recipients, CC: d.CC, BCC: d.BCC, DocumentDate: d.DocumentDate, Subject: d.Subject, MessageID: d.MessageID}
}
