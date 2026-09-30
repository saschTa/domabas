package datasources

import (
	"context"
	"encoding/json"
	"errors"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func (s *DocumentDataSource) UpdateRecord(ctx context.Context, a m.DocumentActor, id string, patch m.DocumentMetadataPatch) (r.DocumentRecord, error) {
	var result r.DocumentRecord
	err := s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		var locked string
		if err := tx.QueryRow(ctx, "SELECT id FROM documents WHERE account_id=$1 AND id=$2 FOR UPDATE", a.AccountID, id).Scan(&locked); err != nil {
			return err
		}
		current, err := readDocument(ctx, tx, a.AccountID, id)
		if err != nil {
			return err
		}
		metadata, err := patch.Apply(m.DocumentMetadata{Title: current.Title, Description: current.Description, Kind: current.Kind, Tags: current.Tags, Sender: current.Sender, Recipients: current.Recipients, CC: current.CC, BCC: current.BCC, DocumentDate: current.DocumentDate, Subject: current.Subject, MessageID: current.MessageID})
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE documents SET metadata_revision=metadata_revision+1,title=$3,description=$4,kind=$5,tags=$6,sender=$7,recipients=$8,cc=$9,bcc=$10,document_date=NULLIF($11,'')::date,subject=$12,message_id=$13 WHERE account_id=$1 AND id=$2`, a.AccountID, id, metadata.Title, metadata.Description, metadata.Kind, metadata.Tags, metadata.Sender, metadata.Recipients, metadata.CC, metadata.BCC, metadata.DocumentDate, metadata.Subject, metadata.MessageID)
		if err != nil {
			return err
		}
		result, err = readDocument(ctx, tx, a.AccountID, id)
		return err
	})
	return result, err
}
func fileReference(ctx context.Context, tx pgx.Tx, account, id string) (r.DocumentReferenceRecord, error) {
	var ref r.DocumentReferenceRecord
	err := tx.QueryRow(ctx, "SELECT account_id,uploader_id,document_id,location,original_filename,media_type,size,sha256,ingested_at FROM document_files WHERE account_id=$1 AND document_id=$2", account, id).Scan(&ref.AccountID, &ref.UploaderID, &ref.DocumentID, &ref.Location, &ref.File.OriginalFilename, &ref.File.MediaType, &ref.File.Size, &ref.File.SHA256, &ref.File.IngestedAt)
	ref.File.UploaderID = ref.UploaderID
	return ref, err
}
func (s *DocumentDataSource) ReferenceRecord(ctx context.Context, a m.DocumentActor, id string) (r.DocumentReferenceRecord, error) {
	var result r.DocumentReferenceRecord
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var err error
		result, err = fileReference(ctx, tx, a.AccountID, id)
		return err
	})
	return result, err
}
func processingRecord(ctx context.Context, tx pgx.Tx, account, id string) (r.DocumentProcessingRecord, error) {
	var p r.DocumentProcessingRecord
	var configuration []byte
	err := tx.QueryRow(ctx, "SELECT state,stage,generation,configuration_revision,updated_at,COALESCE(failure_code,''),configuration,COALESCE(extraction_method,''),COALESCE(extraction_engine,''),COALESCE(extraction_engine_version,'') FROM document_processing WHERE account_id=$1 AND document_id=$2", account, id).Scan(&p.State, &p.Stage, &p.Generation, &p.ConfigurationRevision, &p.UpdatedAt, &p.FailureCode, &configuration, &p.ExtractionMethod, &p.ExtractionEngine, &p.ExtractionEngineVersion)
	if err == nil {
		err = json.Unmarshal(configuration, &p.Configuration)
		if err == nil {
			ai, e := scanAI(tx.QueryRow(ctx, "SELECT "+aiSummaryColumns+" FROM document_ai_jobs WHERE account_id=$1 AND document_id=$2 AND generation=$3 ORDER BY attempt DESC LIMIT 1", account, id, p.Generation))
			if e == nil {
				p.AI = &ai
			} else if !errors.Is(e, pgx.ErrNoRows) {
				err = e
			}
		}
	}
	return p, err
}
func (s *DocumentDataSource) ProcessingRecord(ctx context.Context, a m.DocumentActor, id string) (r.DocumentProcessingRecord, error) {
	var p r.DocumentProcessingRecord
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error { var err error; p, err = processingRecord(ctx, tx, a.AccountID, id); return err })
	return p, err
}
func (s *DocumentDataSource) RetryFacts(ctx context.Context, a m.DocumentActor, id string) (m.DocumentRetryFacts, error) {
	var facts m.DocumentRetryFacts
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var err error
		facts.Configuration, err = readConfiguration(ctx, tx)
		if err != nil {
			return err
		}
		return tx.QueryRow(ctx, "SELECT p.state,p.generation,d.ocr_machine_text IS NOT NULL FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2", a.AccountID, id).Scan(&facts.State, &facts.Generation, &facts.HasMachineText)
	})
	return facts, err
}
func (s *DocumentDataSource) RetryRecord(ctx context.Context, a m.DocumentActor, id string, command m.DocumentRetryCommand) (r.DocumentProcessingRecord, error) {
	var result r.DocumentProcessingRecord
	err := s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		var err error
		result, err = applyDocumentRetry(ctx, tx, a, id, command)
		return err
	})
	return result, err
}
func (s *DocumentDataSource) GetConfigurationRecord(ctx context.Context, a m.DocumentActor) (r.DocumentConfigurationRecord, error) {
	var result m.DocumentProcessingConfiguration
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error { var err error; result, err = readConfiguration(ctx, tx); return err })
	result.DashboardURL = s.dashboardURL
	return s.scheduledConfigurationRecordMapper(result), err
}
func configurationRecord(c m.DocumentProcessingConfiguration) r.DocumentConfigurationRecord {
	result := r.DocumentConfigurationRecord{LLM: r.DocumentLLMConfigurationRecord(c.LLM), ManifestRevision: c.ManifestRevision, Fingerprint: c.Fingerprint, ExtractionRevision: c.ExtractionRevision, ChunkingRevision: c.ChunkingRevision, EmbeddingInputRevision: c.EmbeddingInputRevision, IndexingRevision: c.IndexingRevision, DashboardURL: c.DashboardURL, AutomaticBatchID: c.AutomaticBatchID, ExpectedRevision: c.ExpectedRevision, Revision: c.Revision, Language: c.Language, Segmentation: c.Segmentation, Engine: c.Engine, EngineVersion: c.EngineVersion, EmbeddingModel: c.EmbeddingModel, EmbeddingDigest: c.EmbeddingDigest, Dimensions: c.Dimensions, Ready: c.Ready, Weights: make([]r.DocumentWeightRecord, 0, len(c.Weights))}
	for _, w := range c.Weights {
		result.Weights = append(result.Weights, r.DocumentWeightRecord(w))
	}
	return result
}
func staleError(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return m.ErrStaleJob
	}
	return err
}

func applyDocumentRetry(ctx context.Context, tx pgx.Tx, a m.DocumentActor, id string, command m.DocumentRetryCommand) (r.DocumentProcessingRecord, error) {
	c, err := prepareGeneration(ctx, tx)
	if err != nil {
		return r.DocumentProcessingRecord{}, err
	}
	if err := lockDocument(ctx, tx, a.AccountID, id); err != nil {
		return r.DocumentProcessingRecord{}, err
	}
	var state string
	var machine *string
	var generation int64
	if err := tx.QueryRow(ctx, "SELECT p.state,p.generation,d.ocr_machine_text FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2 FOR UPDATE OF p", a.AccountID, id).Scan(&state, &generation, &machine); err != nil {
		return r.DocumentProcessingRecord{}, err
	}
	if state != command.Expected.State || generation != command.Expected.Generation || (machine != nil) != command.Expected.HasMachineText || c.Revision != command.Expected.Configuration.Revision || c.Fingerprint != command.Expected.Configuration.Fingerprint {
		return r.DocumentProcessingRecord{}, m.ErrConflict
	}
	snapshot, err := json.Marshal(c)
	if err != nil {
		return r.DocumentProcessingRecord{}, err
	}
	_, err = tx.Exec(ctx, `UPDATE document_processing SET split_pipeline=true,generation=$6,generation_sequence=nextval('document_processing_event_seq'),reason='retry',initiated_by_user_id=$5,parent_batch_id=NULL,extraction_method=NULL,extraction_engine=NULL,extraction_engine_version=NULL,requires_extraction=true,ocr_revision=(SELECT ocr_revision FROM documents WHERE account_id=$1 AND id=$2),state='queued',stage='queued',failure_code=NULL,configuration_revision=$3,configuration=$4,updated_at=clock_timestamp(),delivery_deadline=NULL,processing_deadline=NULL,processing_started_at=NULL,unlimited_inference=false,workflow_id='',run_id='',next_check_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2`, a.AccountID, id, c.Revision, snapshot, a.UserID, command.Generation)
	if err != nil {
		return r.DocumentProcessingRecord{}, err
	}
	if _, err = tx.Exec(ctx, "DELETE FROM document_chunks WHERE account_id=$1 AND document_id=$2 AND generation<>$3", a.AccountID, id, generation); err != nil {
		return r.DocumentProcessingRecord{}, err
	}
	if _, err = tx.Exec(ctx, "UPDATE document_chunks SET generation=$3,embedding=NULL,model_digest=NULL WHERE account_id=$1 AND document_id=$2", a.AccountID, id, command.Generation); err != nil {
		return r.DocumentProcessingRecord{}, err
	}
	if _, err = tx.Exec(ctx, "DELETE FROM document_outbox WHERE account_id=$1 AND document_id=$2", a.AccountID, id); err != nil {
		return r.DocumentProcessingRecord{}, err
	}
	if err = insertOutbox(ctx, tx, m.DocumentJob{AccountID: a.AccountID, DocumentID: id, Generation: command.Generation}, c); err != nil {
		return r.DocumentProcessingRecord{}, err
	}
	return processingRecord(ctx, tx, a.AccountID, id)
}
