package datasources

import (
	"context"
	"crypto/cipher"
	"crypto/rand"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func NewDocumentLLMDataSource(database *postgres.PostgresDatabase, publication DocumentPublicationStore, dashboard string, vault cipher.AEAD, scheduler DocumentResourceScheduler, limits ...r.DocumentIngestionLimits) *DocumentDataSource {
	s := NewDocumentIngestionDataSource(database, publication, scheduler, dashboard)
	s.vault = vault
	if len(limits) > 0 {
		s.limits = limits[0]
	}
	return s
}

func CredentialVault(key string) (cipher.AEAD, error) { return credentialCipher(key) }

func (s *DocumentDataSource) storeLLMCredential(ctx context.Context, tx pgx.Tx, command *m.DocumentLLMCredentialWrite) error {
	if command == nil {
		return nil
	}
	if s.vault == nil {
		return m.ErrUnavailable
	}
	nonce := make([]byte, s.vault.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return err
	}
	encrypted := s.vault.Seal(nonce, nonce, []byte(command.Key), []byte(command.ID))
	_, err := tx.Exec(ctx, "INSERT INTO document_llm_credentials(id,encrypted_key) VALUES($1,$2)", command.ID, encrypted)
	return err
}

func (s *DocumentDataSource) credential(ctx context.Context, tx pgx.Tx, id string) (string, error) {
	if id == "" {
		return "", nil
	}
	if s.vault == nil {
		return "", m.ErrUnavailable
	}
	var encrypted []byte
	if err := tx.QueryRow(ctx, "SELECT encrypted_key FROM document_llm_credentials WHERE id=$1", id).Scan(&encrypted); err != nil {
		return "", m.ErrUnavailable
	}
	if len(encrypted) < s.vault.NonceSize() {
		return "", m.ErrUnavailable
	}
	plain, err := s.vault.Open(nil, encrypted[:s.vault.NonceSize()], encrypted[s.vault.NonceSize():], []byte(id))
	if err != nil {
		return "", m.ErrUnavailable
	}
	defer clear(plain)
	return string(plain), nil
}

func (s *DocumentDataSource) PropertyWorkRecord(ctx context.Context, job m.DocumentJob) (r.DocumentPropertyWorkRecord, error) {
	if job.AIAttempt > 0 {
		return s.aiPropertyWork(ctx, job)
	}
	var result r.DocumentPropertyWorkRecord
	work, err := s.WorkRecord(ctx, job, "enriching")
	if err != nil {
		return result, err
	}
	result.Stage, result.Configuration, result.Revision = work.Stage, work.Configuration.LLM, work.Revision
	result.Eligible = work.Eligible
	if work.Stage != "enriching" {
		return result, nil
	}
	err = pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if _, err := lockJob(ctx, tx, job); err != nil {
			return err
		}
		if err := lockRevision(ctx, tx, job, work.Revision); err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, "SELECT COALESCE(ocr_manual_text,ocr_machine_text,''),metadata_revision FROM documents WHERE account_id=$1 AND id=$2", job.AccountID, job.DocumentID).Scan(&result.Text, &result.MetadataRevision); err != nil {
			return err
		}
		result.Metadata, err = readDocument(ctx, tx, job.AccountID, job.DocumentID)
		return err
	})
	return result, err
}

func (s *DocumentDataSource) PropertyCredential(ctx context.Context, id string) (string, error) {
	var result string
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error { var err error; result, err = s.credential(ctx, tx, id); return err })
	return result, err
}

func (s *DocumentDataSource) SaveProperties(ctx context.Context, work m.DocumentPropertyWork, values m.DocumentMetadata) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		j := work.Job
		if j.AIAttempt > 0 {
			return saveAIProperties(ctx, tx, work, values)
		}
		stage, err := lockJob(ctx, tx, j)
		if err != nil {
			return err
		}
		if err := lockRevision(ctx, tx, j, work.Revision); err != nil {
			return err
		}
		if stage == "embedding" || stage == "finalizing" {
			return nil
		}
		if stage != "enriching" {
			return m.ErrStaleJob
		}
		c, err := jobConfiguration(ctx, tx, j)
		if err != nil {
			return err
		}
		if !c.LLM.Equal(work.Configuration) {
			return m.ErrStaleJob
		}
		_, err = tx.Exec(ctx, `UPDATE documents SET description=$4,tags=$5,sender=$6,recipients=$7,document_date=NULLIF($8,'')::date,subject=$9 WHERE account_id=$1 AND id=$2 AND metadata_revision=$3`, j.AccountID, j.DocumentID, work.MetadataRevision, values.Description, values.Tags, values.Sender, values.Recipients, values.DocumentDate, values.Subject)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, "UPDATE document_processing SET stage=$4,updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3", j.AccountID, j.DocumentID, j.Generation, work.NextStage)
		return err
	})
}
