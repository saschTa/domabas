package models

import (
	"io"
	"time"
)

type DocumentActor struct {
	ImportRunID                      string
	ImportClaimToken                 string
	ImportSourceID                   int64
	AccountID, UserID, SessionDigest string
	CredentialRevision               int64
}
type DocumentMetadata struct {
	Title, Description, Kind, Sender, DocumentDate, Subject, MessageID string
	Tags, Recipients, CC, BCC                                          []string
}
type DocumentMetadataPatch struct {
	Title, Description, Kind, Sender, DocumentDate, Subject, MessageID *string
	Tags, Recipients, CC, BCC                                          *[]string
}
type DocumentUploadReservation struct {
	ID, AccountID, UploaderID string
	ExpiresAt                 time.Time
}
type DocumentFileReference struct {
	AccountID, UploaderID, DocumentID, Location string
	File                                        DocumentFile
}
type DocumentFile struct {
	OriginalFilename, MediaType, SHA256, UploaderID string
	Size                                            int64
	IngestedAt                                      time.Time
}
type DocumentContent struct {
	Reader io.ReadCloser
	File   DocumentFile
}
type DocumentProcessingConfiguration struct {
	Scheduling                                                                                  *DocumentProcessingScheduling `json:"-"`
	LLM                                                                                         DocumentLLMConfiguration
	LLMUpdate                                                                                   *DocumentLLMConfigurationUpdate `json:"-"`
	ManifestRevision                                                                            int64
	Fingerprint, ExtractionRevision, ChunkingRevision, EmbeddingInputRevision, IndexingRevision string
	DashboardURL, AutomaticBatchID                                                              string
	ExpectedRevision                                                                            *int64
	Revision                                                                                    int64
	Language, Segmentation, Engine, EngineVersion, EmbeddingModel, EmbeddingDigest              string
	Weights                                                                                     []DocumentWeight
	Dimensions                                                                                  int
	Ready                                                                                       bool
}
type DocumentProcessingScheduling struct {
	IngestionConcurrency, AIConcurrency, OllamaQueueSize, ProviderStepRetries int
	IngestionConcurrencyMode, AIConcurrencyMode, PriorityPolicy               string
}
type DocumentWeight struct{ Name, SHA256 string }
type DocumentProcessing struct {
	AI                                                          *DocumentAIProcessing
	ExtractionMethod, ExtractionEngine, ExtractionEngineVersion string
	State, Stage, FailureCode                                   string
	Generation, ConfigurationRevision                           int64
	UpdatedAt                                                   time.Time
	Configuration                                               DocumentProcessingConfiguration
}
type DocumentJob struct {
	AIAttempt             int64
	AccountID, DocumentID string
	Generation            int64
}
type DocumentOutboxLease struct {
	SplitPipeline                bool
	UnlimitedInference           bool
	WorkflowID, TaskQueue, RunID string
	PermitEnd                    time.Time
	ID, LeaseToken               string
	Job                          DocumentJob
	DeliveryDeadline             time.Time
	ConfigurationRevision        int64
}
type DocumentPendingJob struct {
	SplitPipeline            bool
	UnlimitedInference       bool
	LeaseToken, TaskQueue    string
	LatestPermitEnd          *time.Time
	Legacy                   bool
	Job                      DocumentJob
	WorkflowID, RunID, State string
	DeliveryDeadline         time.Time
	ProcessingDeadline       *time.Time
}
type DocumentProcessingWork struct {
	Eligible, UnlimitedInference, SplitPipeline, EmbeddingsComplete bool
	ManualText                                                      *string
	Revision                                                        int64
	Job                                                             DocumentJob
	Reference                                                       DocumentFileReference
	Configuration                                                   DocumentProcessingConfiguration
	State, Stage                                                    string
	Chunks                                                          []DocumentChunk
}
type DocumentChunk struct {
	Position int
	Text     string
	Vector   []float64
}
type DocumentExtraction struct {
	InvoiceFailureCode    string
	InvoiceXML            []byte
	ExtractionRevision    string
	Text                  string
	Pages                 int
	Engine, EngineVersion string
	Weights               []DocumentWeight
}
type DocumentExtractionIdentity struct {
	Method, Engine, EngineVersion string
	Weights                       []DocumentWeight
}
type DocumentEmbedding struct {
	Space         DocumentEmbeddingSpace
	Model, Digest string
	Vectors       [][]float64
}
type DocumentSearchInput struct {
	Space                           DocumentEmbeddingSpace
	Query, Mode                     string
	Sender, Recipient, Sort, Cursor string
	SenderMatch, RecipientMatch     string
	Tags                            []string
	Kinds                           []string
	Limit, Offset                   int
}
type SearchDocument struct {
	Thumbnail                                      *DocumentThumbnail
	ID, Title, Kind, DocumentDate, ProcessingState string
	Tags                                           []string
	CreatedAt                                      time.Time
	Original                                       *DocumentSearchOriginal
}
type DocumentSearchOriginal struct {
	SHA256, MediaType string
	Size              int64
}
type DocumentSearchResult struct {
	Document SearchDocument
	Score    float64
	Snippet  string
}
type DocumentSearchResults struct {
	Items      []DocumentSearchResult
	Total      *int64
	NextCursor string
}
type DocumentProcessingError struct {
	Code      string
	Retryable bool
}
