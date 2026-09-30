package datasources

import (
	"context"
	"encoding/json"
	"reflect"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func coordinate(ctx context.Context, tx pgx.Tx) error {
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended(current_database()||':'||current_schema()||':document-processing',0))`)
	return err
}
func coordinateDocumentPublication(ctx context.Context, tx pgx.Tx) error {
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock_shared(hashtextextended(current_database()||':'||current_schema()||':document-processing',0))`)
	return err
}
func readConfiguration(ctx context.Context, tx pgx.Tx) (m.DocumentProcessingConfiguration, error) {
	c := m.DefaultConfiguration()
	var snapshot []byte
	var batch *string
	var manifest *int64
	var fingerprint *string
	var contextLength int
	var compatibility, propertyThinking, invoiceThinking bool
	err := tx.QueryRow(ctx, `SELECT revision,language,segmentation,configuration,manifest_revision,manifest_fingerprint,automatic_batch_id::text,llm_context_length,llm_lm_studio_compatibility,llm_property_thinking_enabled,llm_invoice_thinking_enabled FROM document_processing_configuration WHERE id=true`).Scan(&c.Revision, &c.Language, &c.Segmentation, &snapshot, &manifest, &fingerprint, &batch, &contextLength, &compatibility, &propertyThinking, &invoiceThinking)
	if err != nil {
		return c, err
	}
	installed := m.DefaultConfiguration()
	expected, _ := installed.ManifestFingerprint()
	if manifest != nil && (*manifest > installed.ManifestRevision || (*manifest == installed.ManifestRevision && (fingerprint == nil || *fingerprint != expected))) {
		return c, m.ErrUnavailable
	}
	if len(snapshot) > 0 {
		c = m.DocumentProcessingConfiguration{}
		if err = json.Unmarshal(snapshot, &c); err != nil {
			return c, err
		}
	} else {
		c.Fingerprint, err = c.CanonicalFingerprint()
	}
	computed, computeErr := c.CanonicalFingerprint()
	if computeErr != nil {
		return c, computeErr
	}
	if computed != c.Fingerprint || c.LLM.ContextLength != contextLength || c.LLM.LMStudioCompatibility != compatibility || c.LLM.PropertyThinkingEnabled != propertyThinking || c.LLM.InvoiceThinkingEnabled != invoiceThinking {
		return c, m.ErrUnavailable
	}
	if batch != nil {
		c.AutomaticBatchID = *batch
	}
	return c, err
}
func storeConfiguration(ctx context.Context, tx pgx.Tx, c m.DocumentProcessingConfiguration) error {
	c.Ready = false
	c.ExpectedRevision = nil
	c.DashboardURL = ""
	c.AutomaticBatchID = ""
	encoded, err := json.Marshal(c)
	if err != nil {
		return err
	}
	manifest, err := c.ManifestFingerprint()
	if err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE document_processing_configuration SET revision=$1,language=$2,segmentation=$3,configuration=$4,fingerprint=$5,manifest_revision=$6,manifest_fingerprint=$7,llm_context_length=$8,llm_lm_studio_compatibility=$9,llm_property_thinking_enabled=$10,llm_invoice_thinking_enabled=$11 WHERE id=true`, c.Revision, c.Language, c.Segmentation, encoded, c.Fingerprint, c.ManifestRevision, manifest, c.LLM.ContextLength, c.LLM.LMStudioCompatibility, c.LLM.PropertyThinkingEnabled, c.LLM.InvoiceThinkingEnabled); err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO document_processing_configurations(revision,configuration,fingerprint) VALUES($1,$2,$3) ON CONFLICT(revision) DO NOTHING`, c.Revision, encoded, c.Fingerprint)
	return err
}
func automaticBatch(ctx context.Context, tx pgx.Tx, c m.DocumentProcessingConfiguration, reason string) (string, error) {
	if _, err := tx.Exec(ctx, `UPDATE document_reindex_batches SET status='superseded',enumeration_complete=true,finished_at=clock_timestamp() WHERE status IN ('enumerating','running') AND configuration_revision<>$1`, c.Revision); err != nil {
		return "", err
	}
	id := uuid.NewString()
	err := tx.QueryRow(ctx, `INSERT INTO document_reindex_batches(id,reason,configuration_revision,configuration_fingerprint,cutoff_sequence) VALUES($1,$2,$3,$4,nextval('document_processing_event_seq')) ON CONFLICT(configuration_revision) WHERE reason IN ('configuration_change','adoption') DO UPDATE SET id=document_reindex_batches.id RETURNING id`, id, reason, c.Revision, c.Fingerprint).Scan(&id)
	if err != nil {
		return "", err
	}
	_, err = tx.Exec(ctx, `UPDATE document_processing_configuration SET automatic_batch_id=$1 WHERE id=true`, id)
	return id, err
}
func readInitializationFacts(ctx context.Context, tx pgx.Tx, lock bool) (m.DocumentInitializationFacts, error) {
	var facts m.DocumentInitializationFacts
	var snapshot []byte
	suffix := ""
	if lock {
		suffix = " FOR UPDATE"
	}
	err := tx.QueryRow(ctx, "SELECT adopted,revision,language,segmentation,configuration,manifest_revision,manifest_fingerprint,llm_context_length,llm_lm_studio_compatibility,llm_property_thinking_enabled,llm_invoice_thinking_enabled FROM document_processing_configuration WHERE id=true"+suffix).Scan(&facts.Adopted, &facts.Revision, &facts.Language, &facts.Segmentation, &snapshot, &facts.ManifestRevision, &facts.ManifestFingerprint, &facts.ContextLength, &facts.LMStudioCompatibility, &facts.PropertyThinkingEnabled, &facts.InvoiceThinkingEnabled)
	if err != nil {
		return facts, err
	}
	facts.SnapshotPresent = len(snapshot) > 0
	if facts.SnapshotPresent {
		if err = json.Unmarshal(snapshot, &facts.Previous); err != nil {
			return facts, err
		}
		actual, err := facts.Previous.CanonicalFingerprint()
		if err != nil {
			return facts, err
		}
		if actual != facts.Previous.Fingerprint {
			return facts, m.ErrUnavailable
		}
	}
	return facts, nil
}
func initializationDrift(ctx context.Context, tx pgx.Tx, fingerprint string) (bool, error) {
	var drift bool
	err := tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM document_processing p JOIN document_files f ON f.document_id=p.document_id JOIN documents d ON d.id=p.document_id WHERE p.configuration->>'Fingerprint'<>$1 OR (d.machine_extraction_fingerprint IS NOT NULL AND d.machine_extraction_fingerprint<>$1))", fingerprint).Scan(&drift)
	return drift, err
}
func (s *DocumentDataSource) InitializationFacts(ctx context.Context) (m.DocumentInitializationFacts, error) {
	var facts m.DocumentInitializationFacts
	err := pgx.BeginTxFunc(ctx, s.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error { var err error; facts, err = readInitializationFacts(ctx, tx, false); return err })
	return facts, err
}
func (s *DocumentDataSource) InitializationDrift(ctx context.Context, fingerprint string) (bool, error) {
	var drift bool
	err := pgx.BeginTxFunc(ctx, s.database, pgx.TxOptions{AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		var err error
		drift, err = initializationDrift(ctx, tx, fingerprint)
		return err
	})
	return drift, err
}
func (s *DocumentDataSource) InitializeConfiguration(ctx context.Context, command m.DocumentInitializationCommand) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		facts, err := readInitializationFacts(ctx, tx, true)
		if err != nil {
			return err
		}
		if !reflect.DeepEqual(facts, command.Expected) {
			return m.ErrConflict
		}
		if command.CheckDrift {
			drift, err := initializationDrift(ctx, tx, command.Configuration.Fingerprint)
			if err != nil {
				return err
			}
			if drift != command.Drift {
				return m.ErrConflict
			}
		}
		if err = storeConfiguration(ctx, tx, command.Configuration); err != nil {
			return err
		}
		if command.BatchReason != "" {
			if _, err = automaticBatch(ctx, tx, command.Configuration, command.BatchReason); err != nil {
				return err
			}
		}
		if command.RescheduleAI {
			if _, err = tx.Exec(ctx, "UPDATE document_processing_configuration SET ai_reschedule_revision=$1,ai_reschedule_cutoff=nextval('document_processing_event_seq'),ai_reschedule_cursor=0 WHERE id=true", command.Configuration.Revision); err != nil {
				return err
			}
		}
		_, err = tx.Exec(ctx, "UPDATE document_processing_configuration SET adopted=true WHERE id=true")
		return err
	})
}
func prepareGeneration(ctx context.Context, tx pgx.Tx) (m.DocumentProcessingConfiguration, error) {
	if err := coordinateDocumentPublication(ctx, tx); err != nil {
		return m.DocumentProcessingConfiguration{}, err
	}
	return readConfiguration(ctx, tx)
}
func (s *DocumentDataSource) ProcessingReady(ctx context.Context) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error { _, err := readConfiguration(ctx, tx); return err })
}
func (s *DocumentDataSource) SetConfigurationRecord(ctx context.Context, a m.DocumentActor, command m.DocumentConfigurationChange) (r.DocumentConfigurationRecord, error) {
	result := command.Configuration
	err := s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		current, err := readConfiguration(ctx, tx)
		if err != nil {
			return err
		}
		if current.Revision != command.ExpectedRevision {
			return m.ErrConflict
		}
		if err = s.storeLLMCredential(ctx, tx, command.Credential); err != nil {
			return err
		}
		if err = storeConfiguration(ctx, tx, result); err != nil {
			return err
		}
		if command.Reindex {
			result.AutomaticBatchID, err = automaticBatch(ctx, tx, result, "configuration_change")
			if err != nil {
				return err
			}
		} else {
			result.AutomaticBatchID = ""
			if _, err = tx.Exec(ctx, "UPDATE document_processing_configuration SET automatic_batch_id=NULL WHERE id=true"); err != nil {
				return err
			}
		}
		if command.RescheduleAI {
			_, err = tx.Exec(ctx, "UPDATE document_processing_configuration SET ai_reschedule_revision=$1,ai_reschedule_cutoff=nextval('document_processing_event_seq'),ai_reschedule_cursor=0 WHERE id=true", result.Revision)
		} else {
			_, err = tx.Exec(ctx, "UPDATE document_processing_configuration SET ai_reschedule_revision=NULL,ai_reschedule_cutoff=NULL,ai_reschedule_cursor=0 WHERE id=true")
		}
		return err
	})
	result.DashboardURL = s.dashboardURL
	return s.scheduledConfigurationRecordMapper(result), err
}
func (s *DocumentDataSource) NamespaceConfigurationRecord(ctx context.Context, a m.DocumentActor) (r.DocumentConfigurationRecord, error) {
	var result m.DocumentProcessingConfiguration
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error { var err error; result, err = readConfiguration(ctx, tx); return err })
	return s.scheduledConfigurationRecordMapper(result), err
}
func (s *DocumentDataSource) SearchConfigurationRecord(ctx context.Context, a m.DocumentActor) (r.DocumentConfigurationRecord, error) {
	var result m.DocumentProcessingConfiguration
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error { var err error; result, err = readConfiguration(ctx, tx); return err })
	return configurationRecord(result), err
}
