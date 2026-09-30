package services

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"time"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type DocumentIngestionService struct {
	repository   p.DocumentIngestionRepository
	authority    p.DocumentAuthority
	store        p.DocumentContentStore
	processor    p.DocumentProcessor
	modelContext p.DocumentModelContextReader
	now          func() time.Time
}

func NewDocumentIngestionService(repository p.DocumentIngestionRepository, store p.DocumentContentStore, processor p.DocumentProcessor, authority p.DocumentAuthority, now func() time.Time, readers ...p.DocumentModelContextReader) *DocumentIngestionService {
	service := &DocumentIngestionService{repository: repository, authority: authority, store: store, processor: processor, now: now}
	if len(readers) > 0 {
		service.modelContext = readers[0]
	}
	return service
}

func (s *DocumentIngestionService) ModelContext(ctx context.Context, a m.DocumentActor, model string) (m.DocumentModelContext, error) {
	if err := s.authorize(ctx, a, identity.SystemDocumentProcessingManage); err != nil {
		return m.DocumentModelContext{}, err
	}
	if _, err := s.repository.GetConfiguration(ctx, a); err != nil {
		return m.DocumentModelContext{}, err
	}
	input, err := (m.DocumentLLMConfigurationUpdate{Provider: "ollama", Model: model}).Normalize()
	if err != nil {
		return m.DocumentModelContext{}, err
	}
	if s.modelContext == nil {
		return m.DocumentModelContext{}, m.ErrUnavailable
	}
	return s.modelContext.ModelContext(ctx, input.Model)
}
func documentID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[:4], b[4:6], b[6:8], b[8:10], b[10:]), nil
}
func (s *DocumentIngestionService) ReserveUpload(ctx context.Context, a m.DocumentActor) (m.DocumentUploadReservation, error) {
	if err := s.authorize(ctx, a, identity.DocumentsUpload); err != nil {
		return m.DocumentUploadReservation{}, err
	}
	id, err := documentID()
	if err != nil {
		return m.DocumentUploadReservation{}, err
	}
	return s.repository.Reserve(ctx, a, m.DocumentUploadReservation{ID: id, AccountID: a.AccountID, UploaderID: a.UserID, ExpiresAt: s.now().UTC().Add(5 * time.Minute)})
}
func (s *DocumentIngestionService) StageUpload(ctx context.Context, a m.DocumentActor, reservation m.DocumentUploadReservation, filename string, reader io.Reader) (m.DocumentFileReference, error) {
	if err := s.authorize(ctx, a, identity.DocumentsUpload); err != nil {
		return m.DocumentFileReference{}, err
	}
	r, err := s.repository.Reservation(ctx, a, reservation.ID)
	if err != nil {
		return m.DocumentFileReference{}, err
	}
	if !r.ExpiresAt.After(s.now()) {
		return m.DocumentFileReference{}, m.ErrConflict
	}
	reference, err := s.store.Stage(ctx, r, filename, reader)
	if err != nil {
		return m.DocumentFileReference{}, err
	}
	if reference.AccountID != r.AccountID || reference.UploaderID != r.UploaderID || reference.DocumentID != r.ID || reference.Location != "staged" {
		return m.DocumentFileReference{}, m.ErrUnavailable
	}
	if err := s.authorize(ctx, a, identity.DocumentsUpload); err != nil {
		return m.DocumentFileReference{}, err
	}
	if err := s.repository.RecordStaged(ctx, a, r.ID, reference); err != nil {
		return m.DocumentFileReference{}, err
	}
	return reference, nil
}
func (s *DocumentIngestionService) AcceptUpload(ctx context.Context, a m.DocumentActor, r m.DocumentUploadReservation, metadata m.DocumentMetadata) (m.Document, error) {
	if err := s.authorize(ctx, a, identity.DocumentsUpload); err != nil {
		return m.Document{}, err
	}
	metadata, err := metadata.Normalize()
	if err != nil {
		return m.Document{}, err
	}
	facts, err := s.repository.UploadAcceptanceFacts(ctx, a, r.ID)
	if err != nil {
		return m.Document{}, err
	}
	command, err := m.PlanDocumentUploadAcceptance(facts, metadata, s.now().UTC())
	if err != nil {
		return m.Document{}, err
	}
	return s.repository.Accept(ctx, a, r.ID, command)
}
func (s *DocumentIngestionService) AbandonUpload(ctx context.Context, a m.DocumentActor, r m.DocumentUploadReservation) error {
	if err := s.authorize(ctx, a, identity.DocumentsUpload); err != nil {
		return err
	}
	ref, err := s.repository.Abandon(ctx, a, r.ID)
	if err != nil || ref == nil {
		return err
	}
	if err = s.store.Remove(ctx, *ref); err != nil {
		return err
	}
	return s.repository.Reaped(ctx, *ref, m.DocumentStagedUploadRetention())
}
func (s *DocumentIngestionService) ReapUploads(ctx context.Context) error {
	deletionErr := s.reapDeleted(ctx)
	policy := m.DocumentStagedUploadRetention()
	refs, err := s.repository.Reap(ctx, policy)
	if err != nil {
		return errors.Join(deletionErr, err)
	}
	failures := []error{deletionErr}
	for _, ref := range refs {
		if err = s.store.Remove(ctx, ref); err == nil {
			err = s.repository.Reaped(ctx, ref, policy)
		}
		if err != nil {
			failures = append(failures, err)
		}
	}
	return errors.Join(failures...)
}
func (s *DocumentIngestionService) Update(ctx context.Context, a m.DocumentActor, id string, patch m.DocumentMetadataPatch) (m.Document, error) {
	if err := s.authorize(ctx, a, identity.DocumentsUpdate); err != nil {
		return m.Document{}, err
	}
	return s.repository.Update(ctx, a, id, patch)
}
func (s *DocumentIngestionService) OpenContent(ctx context.Context, a m.DocumentActor, id string) (m.DocumentContent, error) {
	if err := s.authorize(ctx, a, identity.DocumentsDownload); err != nil {
		return m.DocumentContent{}, err
	}
	ref, err := s.repository.Reference(ctx, a, id)
	if err != nil {
		return m.DocumentContent{}, err
	}
	reader, err := s.store.Open(ctx, ref)
	if err != nil {
		ref, err = s.repository.Reference(ctx, a, id)
		if err != nil {
			return m.DocumentContent{}, err
		}
		reader, err = s.store.Open(ctx, ref)
	}
	if err == nil {
		if err := s.authorize(ctx, a, identity.DocumentsDownload); err != nil {
			_ = reader.Close()
			return m.DocumentContent{}, err
		}
	}
	return m.DocumentContent{Reader: reader, File: ref.File}, err
}
func (s *DocumentIngestionService) Processing(ctx context.Context, a m.DocumentActor, id string) (m.DocumentProcessing, error) {
	if err := s.authorize(ctx, a, identity.DocumentsRead); err != nil {
		return m.DocumentProcessing{}, err
	}
	return s.repository.Processing(ctx, a, id)
}
func (s *DocumentIngestionService) Retry(ctx context.Context, a m.DocumentActor, id string) (m.DocumentProcessing, error) {
	if err := s.authorize(ctx, a, identity.DocumentsRetry); err != nil {
		return m.DocumentProcessing{}, err
	}
	facts, err := s.repository.RetryFacts(ctx, a, id)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	command, err := m.PlanDocumentRetry(facts)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	return s.repository.Retry(ctx, a, id, command)
}
func (s *DocumentIngestionService) Search(ctx context.Context, a m.DocumentActor, input m.DocumentSearchInput) (m.DocumentSearchResults, error) {
	if err := s.authorize(ctx, a, identity.DocumentsSearch); err != nil {
		return m.DocumentSearchResults{}, err
	}
	input, err := input.Normalize()
	if err != nil {
		return m.DocumentSearchResults{}, err
	}
	var vector []float64
	if input.UsesEmbeddings() {
		configuration, e := s.repository.SearchConfiguration(ctx, a)
		if e != nil {
			return m.DocumentSearchResults{}, e
		}
		input.Space = configuration.EmbeddingSpace()
		embedding, e := s.processor.Embed(ctx, input.Space, "query", []string{input.Query})
		if e != nil {
			return m.DocumentSearchResults{}, m.ErrUnavailable
		}
		if embedding.Space != input.Space || embedding.Model != input.Space.Model || embedding.Digest != input.Space.Digest || len(embedding.Vectors) != 1 {
			return m.DocumentSearchResults{}, m.ErrUnavailable
		}
		vector, e = m.NormalizeVector(embedding.Vectors[0])
		if e != nil {
			return m.DocumentSearchResults{}, m.ErrUnavailable
		}
	}
	if len(vector) > 0 {
		if err := s.authorize(ctx, a, identity.DocumentsSearch); err != nil {
			return m.DocumentSearchResults{}, err
		}
	}
	return s.repository.Search(ctx, a, input, vector)
}
func (s *DocumentIngestionService) GetProcessingConfiguration(ctx context.Context, a m.DocumentActor) (m.DocumentProcessingConfiguration, error) {
	if err := s.authorize(ctx, a, identity.SystemDocumentProcessingManage); err != nil {
		return m.DocumentProcessingConfiguration{}, err
	}
	c, err := s.repository.GetConfiguration(ctx, a)
	if err == nil {
		c.Ready = s.processor.Ready(ctx) == nil
	}
	return c, err
}
func (s *DocumentIngestionService) SetProcessingConfiguration(ctx context.Context, a m.DocumentActor, c m.DocumentProcessingConfiguration) (m.DocumentProcessingConfiguration, error) {
	if err := s.authorize(ctx, a, identity.SystemDocumentProcessingManage); err != nil {
		return m.DocumentProcessingConfiguration{}, err
	}
	if err := c.Validate(); err != nil {
		return m.DocumentProcessingConfiguration{}, err
	}
	current, err := s.repository.GetConfiguration(ctx, a)
	if err != nil {
		return m.DocumentProcessingConfiguration{}, err
	}
	change, err := s.configurationChange(ctx, current, c)
	if err != nil {
		return m.DocumentProcessingConfiguration{}, err
	}
	result := current
	if change.Configuration.Revision != current.Revision {
		if err = s.authorize(ctx, a, identity.SystemDocumentProcessingManage); err != nil {
			return m.DocumentProcessingConfiguration{}, err
		}
		result, err = s.repository.SetConfiguration(ctx, a, change)
	}
	if err == nil {
		result.Ready = s.processor.Ready(ctx) == nil
	}
	return result, err
}
func (s *DocumentIngestionService) Extract(ctx context.Context, job m.DocumentJob) error {
	work, err := s.Work(ctx, job, "extracting")
	if err != nil {
		return err
	}
	if work.Stage != "extracting" {
		return nil
	}
	reader, err := s.store.Open(ctx, work.Reference)
	if err != nil {
		return m.DocumentProcessingError{Code: "storage_unavailable", Retryable: true}
	}
	defer reader.Close()
	extraction, err := s.processor.Extract(ctx, reader, work.Reference.File.MediaType, work.Configuration)
	if err != nil {
		return processingError(err)
	}
	if err := work.Configuration.ValidateExtraction(work.Reference.File.MediaType, extraction); err != nil {
		return err
	}
	if _, err = ChunkText(extraction.Text); err != nil {
		return err
	}
	command, err := m.PlanDocumentExtraction(work, work.Revision, extraction)
	if err != nil {
		return err
	}
	return s.repository.SaveExtractionEvidence(ctx, command)
}
func (s *DocumentIngestionService) Embed(ctx context.Context, job m.DocumentJob) error {
	work, err := s.Work(ctx, job, "embedding")
	if err != nil {
		return err
	}
	if work.Stage == "finalizing" {
		return nil
	}
	if work.Stage != "embedding" {
		return m.DocumentProcessingError{Code: "processing_failed"}
	}
	chunks := work.Chunks
	for i := 0; i < len(chunks); {
		end := min(i+8, len(chunks))
		texts := make([]string, end-i)
		for j := i; j < end; j++ {
			texts[j-i] = chunks[j].Text
		}
		embedding, e := s.processor.Embed(ctx, work.Configuration.EmbeddingSpace(), "document", texts)
		if errors.Is(e, m.ErrEmbeddingContextLength) {
			if end-i > 1 {
				end = i + 1
				embedding, e = s.processor.Embed(ctx, work.Configuration.EmbeddingSpace(), "document", texts[:1])
			}
			if errors.Is(e, m.ErrEmbeddingContextLength) {
				runes := []rune(chunks[i].Text)
				if len(runes) < 2 || len(chunks) >= m.MaxOCRChunks {
					return m.DocumentProcessingError{Code: "resource_limit"}
				}
				middle := len(runes) / 2
				parts := []m.DocumentChunk{{Text: string(runes[:middle])}, {Text: string(runes[middle:])}}
				chunks = append(append(append([]m.DocumentChunk{}, chunks[:i]...), parts...), chunks[i+1:]...)
				continue
			}
		}
		if e != nil {
			return processingError(e)
		}
		if embedding.Space != work.Configuration.EmbeddingSpace() || embedding.Model != work.Configuration.EmbeddingModel || embedding.Digest != work.Configuration.EmbeddingDigest || len(embedding.Vectors) != end-i {
			return m.DocumentProcessingError{Code: "processing_failed"}
		}
		for j := i; j < end; j++ {
			chunks[j].Vector, e = m.NormalizeVector(embedding.Vectors[j-i])
			if e != nil {
				return e
			}
		}
		i = end
	}
	for i := range chunks {
		chunks[i].Position = i
	}
	command, err := m.PlanDocumentEmbeddings(work, work.Revision, work.Configuration.EmbeddingSpace(), chunks)
	if err != nil {
		return err
	}
	return s.repository.SaveEmbeddings(ctx, command)
}
func (s *DocumentIngestionService) Finalize(ctx context.Context, job m.DocumentJob) error {
	work, err := s.Work(ctx, job, "finalizing")
	if err != nil {
		return err
	}
	if work.State == "ready" && work.Stage == "complete" {
		return nil
	}
	if work.Stage != "finalizing" {
		return m.DocumentProcessingError{Code: "processing_failed"}
	}
	command, err := m.PlanDocumentPublication(work, work.Revision)
	if err != nil {
		return err
	}
	if err = s.repository.Publish(ctx, command); err != nil {
		return err
	}
	if work.Reference.Location == "staged" {
		_ = s.store.Remove(ctx, work.Reference)
	}
	return nil
}
func (s *DocumentIngestionService) Fail(ctx context.Context, j m.DocumentJob, code string) error {
	if !m.ValidFailureCode(code) {
		code = "processing_failed"
	}
	return s.repository.Fail(ctx, j, code)
}
func (s *DocumentIngestionService) Claim(ctx context.Context, limit int, lease time.Duration, queue ...string) ([]m.DocumentOutboxLease, error) {
	if err := s.MaintainProcessing(ctx); err != nil {
		return nil, err
	}
	facts, err := s.repository.ReindexScheduleFacts(ctx)
	if err != nil {
		return nil, err
	}
	commands := make([]m.DocumentReindexScheduleCommand, len(facts))
	for i, fact := range facts {
		commands[i] = m.PlanDocumentReindexSchedule(fact)
	}
	settings, err := s.repository.DeliverySettings(ctx)
	if err != nil {
		return nil, err
	}
	return s.repository.Claim(ctx, limit, lease, commands, m.PlanDocumentDelivery(settings), queue...)
}
func (s *DocumentIngestionService) Acknowledge(ctx context.Context, l m.DocumentOutboxLease, workflow, run string) error {
	return s.repository.Acknowledge(ctx, l, workflow, run)
}
func (s *DocumentIngestionService) Release(ctx context.Context, l m.DocumentOutboxLease, next time.Time) error {
	return s.repository.Release(ctx, l, next)
}
func (s *DocumentIngestionService) Pending(ctx context.Context, limit int) ([]m.DocumentPendingJob, error) {
	return s.repository.Pending(ctx, limit)
}
func (s *DocumentIngestionService) FailExpired(ctx context.Context, j m.DocumentJob, code string) error {
	if code != "processing_timeout" && code != "delivery_timeout" {
		return m.DocumentValidationError{Message: "invalid deadline failure"}
	}
	return s.repository.FailExpired(ctx, j, code)
}
func processingError(err error) error {
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return err
	}
	var typed m.DocumentProcessingError
	if errors.As(err, &typed) {
		return typed
	}
	if errors.Is(err, m.ErrStaleJob) || errors.Is(err, m.ErrOverloaded) {
		return err
	}
	return m.DocumentProcessingError{Code: "processing_failed", Retryable: true}
}
func ChunkText(text string) ([]m.DocumentChunk, error) {
	chunks, err := m.OCRChunks(text)
	if errors.Is(err, m.ErrTooLarge) {
		return nil, m.DocumentProcessingError{Code: "resource_limit"}
	}
	if err != nil {
		return nil, m.DocumentProcessingError{Code: "processing_failed"}
	}
	return chunks, nil
}

func (s *DocumentIngestionService) ResolveExecution(ctx context.Context, pending m.DocumentPendingJob, run, code string, missing bool) error {
	if code != "" && !m.ValidFailureCode(code) {
		return m.DocumentValidationError{Message: "invalid execution outcome"}
	}
	facts, err := s.repository.ExecutionFacts(ctx, pending)
	if err != nil {
		return err
	}
	plan, err := m.PlanDocumentExecutionRecovery(facts.RunID, run, code, missing, facts.SafeMissing)
	if err != nil {
		return err
	}
	return s.repository.ResolveExecution(ctx, pending, m.DocumentExecutionResolution{ExpectedRunID: facts.RunID, RunID: run, Outcome: code, Close: plan.Close, Missing: missing})
}
