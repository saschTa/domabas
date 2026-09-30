package models

import "time"

type DocumentRecord struct {
	Thumbnail                                                              *DocumentThumbnailRecord
	ID, Title, Description, Kind, Sender, DocumentDate, Subject, MessageID string
	CreatedAt                                                              time.Time
	Tags, Recipients, CC, BCC                                              []string
	File                                                                   *DocumentFileRecord
	Processing                                                             *DocumentProcessingRecord
}
type DocumentReservationRecord struct {
	ID, AccountID, UploaderID string
	ExpiresAt                 time.Time
}
type DocumentFileRecord struct {
	OriginalFilename, MediaType, SHA256, UploaderID string
	Size                                            int64
	IngestedAt                                      time.Time
}
type DocumentReferenceRecord struct {
	AccountID, UploaderID, DocumentID, Location string
	File                                        DocumentFileRecord
}
type DocumentWeightRecord struct{ Name, SHA256 string }
type DocumentLLMConfigurationRecord struct {
	PropertyThinkingEnabled                bool `json:",omitempty"`
	InvoiceThinkingEnabled                 bool `json:",omitempty"`
	LMStudioCompatibility                  bool `json:",omitempty"`
	Enabled                                bool
	InvoiceEnabled                         *bool
	ContextLength                          int
	Provider, Model, BaseURL, CredentialID string
}
type DocumentConfigurationRecord struct {
	Scheduling                                                                                  *DocumentSchedulingRecord
	LLM                                                                                         DocumentLLMConfigurationRecord
	ManifestRevision                                                                            int64
	Fingerprint, ExtractionRevision, ChunkingRevision, EmbeddingInputRevision, IndexingRevision string
	DashboardURL, AutomaticBatchID                                                              string
	ExpectedRevision                                                                            *int64
	Revision                                                                                    int64
	Language, Segmentation, Engine, EngineVersion, EmbeddingModel, EmbeddingDigest              string
	Weights                                                                                     []DocumentWeightRecord
	Dimensions                                                                                  int
	Ready                                                                                       bool
}
type DocumentProcessingRecord struct {
	AI                                                          *DocumentAIProcessingRecord
	ExtractionMethod, ExtractionEngine, ExtractionEngineVersion string
	State, Stage, FailureCode                                   string
	Generation, ConfigurationRevision                           int64
	UpdatedAt                                                   time.Time
	Configuration                                               DocumentConfigurationRecord
}
type DocumentJobRecord struct {
	AIAttempt             int64
	AccountID, DocumentID string
	Generation            int64
}
type DocumentChunkRecord struct {
	Position int
	Text     string
	Vector   []float64
}
type DocumentWorkRecord struct {
	Eligible, UnlimitedInference, SplitPipeline, EmbeddingsComplete bool
	ManualText                                                      *string
	Revision                                                        int64
	Job                                                             DocumentJobRecord
	Reference                                                       DocumentReferenceRecord
	Configuration                                                   DocumentConfigurationRecord
	State, Stage                                                    string
	Chunks                                                          []DocumentChunkRecord
}
type SearchDocumentRecord struct {
	Thumbnail                                      *DocumentThumbnailRecord
	ID, Title, Kind, DocumentDate, ProcessingState string
	Tags                                           []string
	CreatedAt                                      time.Time
	Original                                       *DocumentSearchOriginalRecord
}
type DocumentSearchOriginalRecord struct {
	SHA256, MediaType string
	Size              int64
}
type DocumentSearchItemRecord struct {
	Document SearchDocumentRecord
	Score    float64
	Snippet  string
}
type DocumentSearchRecord struct {
	Items      []DocumentSearchItemRecord
	Total      *int64
	NextCursor string
}
type DocumentLeaseRecord struct {
	SplitPipeline                bool
	UnlimitedInference           bool
	WorkflowID, TaskQueue, RunID string
	PermitEnd                    time.Time
	ID, LeaseToken               string
	Job                          DocumentJobRecord
	DeliveryDeadline             time.Time
	ConfigurationRevision        int64
}
type DocumentPendingRecord struct {
	SplitPipeline            bool
	UnlimitedInference       bool
	LeaseToken, TaskQueue    string
	LatestPermitEnd          *time.Time
	Legacy                   bool
	Job                      DocumentJobRecord
	WorkflowID, RunID, State string
	DeliveryDeadline         time.Time
	ProcessingDeadline       *time.Time
}

type DocumentIngestionLimits struct {
	Concurrency                        int
	AIConcurrency                      int
	OllamaQueueSize                    int
	ConcurrencyMode, AIConcurrencyMode string
	UnlimitedInference                 bool
}

type DocumentSchedulingRecord struct {
	IngestionConcurrency, AIConcurrency, OllamaQueueSize, ProviderStepRetries int
	IngestionConcurrencyMode, AIConcurrencyMode, PriorityPolicy               string
}

type DocumentPropertyWorkRecord struct {
	Eligible                   bool
	Configuration              DocumentLLMConfigurationRecord
	Stage, Text                string
	Revision, MetadataRevision int64
	Metadata                   DocumentRecord
}
