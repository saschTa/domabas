package datasources

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func importAuthorityError(err, missing error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return missing
	}
	return err
}
func (s *DocumentDataSource) ImportConsent(ctx context.Context, a m.DocumentImportAuthority) (int64, error) {
	var revision int64
	err := s.database.QueryRow(ctx, `SELECT consent_revision FROM email_providers WHERE id=$1 AND account_id=$2 AND owner_id=$3 AND revision=$4 AND source_generation=$5 AND enabled AND deleted_at IS NULL`, a.ProviderID, a.AccountID, a.OwnerID, a.ProviderRevision, a.SourceGeneration).Scan(&revision)
	return revision, importAuthorityError(err, m.ErrStaleJob)
}
func (s *DocumentDataSource) importTx(ctx context.Context, a m.DocumentImportAuthority, fn func(context.Context, pgx.Tx) error) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	return documentError(pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='4s'; SET LOCAL statement_timeout='5s'"); err != nil {
			return err
		}
		var id string
		if err := tx.QueryRow(ctx, `SELECT id FROM email_providers WHERE id=$1 AND account_id=$2 AND owner_id=$3 AND revision=$4 AND source_generation=$5 AND consent_revision=$6 AND enabled AND deleted_at IS NULL FOR UPDATE`, a.ProviderID, a.AccountID, a.OwnerID, a.ProviderRevision, a.SourceGeneration, a.CredentialRevision).Scan(&id); err != nil {
			return importAuthorityError(err, m.ErrStaleJob)
		}
		if err := tx.QueryRow(ctx, `SELECT id FROM email_runs WHERE id=$1 AND provider_id=$2 AND provider_revision=$3 AND source_generation=$4 AND mailbox_generation=$5 AND status='running' AND attempt_token=$6 AND attempt_deadline>clock_timestamp() AND workflow_run_id=$7 AND activity_id=$8 AND activity_attempt=$9 AND page_index=$10 FOR UPDATE`, a.RunID, a.ProviderID, a.ProviderRevision, a.SourceGeneration, a.MailboxGeneration, a.AttemptToken, a.WorkflowRunID, a.ActivityID, a.ActivityAttempt, a.PageIndex).Scan(&id); err != nil {
			return importAuthorityError(err, m.ErrStaleJob)
		}
		var generation int64
		if err := tx.QueryRow(ctx, `SELECT mailbox_generation FROM email_mailboxes WHERE provider_id=$1 AND source_generation=$2 FOR UPDATE`, a.ProviderID, a.SourceGeneration).Scan(&generation); err != nil {
			return importAuthorityError(err, m.ErrStaleJob)
		}
		if generation != a.MailboxGeneration {
			return m.ErrStaleJob
		}
		return fn(ctx, tx)
	}))
}
func lockImportPart(ctx context.Context, tx pgx.Tx, a m.DocumentImportAuthority) (string, error) {
	var parent *string
	var state string
	if err := tx.QueryRow(ctx, `SELECT parent_document_id::text,state FROM email_messages WHERE id=$1 AND provider_id=$2 AND account_id=$3 AND owner_id=$4 AND source_generation=$5 AND mailbox_generation=$6 AND run_id=$7 AND provider_revision=$8 AND attempt_token=$9 FOR UPDATE`, a.MessageID, a.ProviderID, a.AccountID, a.OwnerID, a.SourceGeneration, a.MailboxGeneration, a.RunID, a.ProviderRevision, a.AttemptToken).Scan(&parent, &state); err != nil {
		return "", m.ErrStaleJob
	}
	if state == "deleted" || state == "skipped" || state == "failed" {
		return "", m.ErrStaleJob
	}
	if parent != nil {
		var exists bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM documents WHERE account_id=$1 AND id=$2)`, a.AccountID, *parent).Scan(&exists); err != nil {
			return "", err
		}
		if !exists {
			return "", m.ErrNotFound
		}
	}
	var path string
	if err := tx.QueryRow(ctx, `SELECT path FROM email_parts WHERE id=$1 AND message_id=$2 AND account_id=$3 AND attempt_token=$4 FOR UPDATE`, a.PartID, a.MessageID, a.AccountID, a.AttemptToken).Scan(&path); err != nil {
		return "", m.ErrStaleJob
	}
	return path, nil
}
func (s *DocumentDataSource) ReserveImport(ctx context.Context, a m.DocumentImportAuthority, reservation m.DocumentUploadReservation) (m.DocumentUploadReservation, error) {
	err := s.importTx(ctx, a, func(ctx context.Context, tx pgx.Tx) error {
		if _, err := lockImportPart(ctx, tx, a); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE email_parts SET reservation_id=$2,updated_at=clock_timestamp() WHERE id=$1 AND document_id IS NULL AND state='pending'`, a.PartID, reservation.ID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() != 1 {
			return m.ErrConflict
		}
		return tx.QueryRow(ctx, `INSERT INTO document_uploads(id,account_id,uploader_id,expires_at) VALUES($1,$2,$3,$4) RETURNING expires_at`, reservation.ID, a.AccountID, a.OwnerID, reservation.ExpiresAt).Scan(&reservation.ExpiresAt)
	})
	return reservation, err
}
func importReservation(ctx context.Context, tx pgx.Tx, a m.DocumentImportAuthority, id string) error {
	var found string
	err := tx.QueryRow(ctx, `SELECT u.id FROM document_uploads u JOIN email_parts p ON p.reservation_id=u.id WHERE u.id=$1 AND u.account_id=$2 AND u.uploader_id=$3 AND u.state='receiving' AND u.expires_at>clock_timestamp() AND p.id=$4 AND p.attempt_token=$5 FOR UPDATE OF u`, id, a.AccountID, a.OwnerID, a.PartID, a.AttemptToken).Scan(&found)
	if err != nil {
		return m.ErrStaleJob
	}
	return nil
}
func (s *DocumentDataSource) StageImport(ctx context.Context, a m.DocumentImportAuthority, reservation m.DocumentUploadReservation, reference m.DocumentFileReference) error {
	if reference.AccountID != a.AccountID || reference.UploaderID != a.OwnerID || reference.DocumentID != reservation.ID || reference.Location != "staged" {
		return m.ErrConflict
	}
	return s.importTx(ctx, a, func(ctx context.Context, tx pgx.Tx) error {
		if _, err := lockImportPart(ctx, tx, a); err != nil {
			return err
		}
		if err := importReservation(ctx, tx, a, reservation.ID); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE document_uploads SET original_filename=$2,media_type=$3,size=$4,sha256=$5 WHERE id=$1 AND sha256 IS NULL`, reservation.ID, reference.File.OriginalFilename, reference.File.MediaType, reference.File.Size, reference.File.SHA256)
		if err == nil && tag.RowsAffected() != 1 {
			return m.ErrConflict
		}
		return err
	})
}
func (s *DocumentDataSource) ImportAcceptanceFacts(ctx context.Context, a m.DocumentImportAuthority, reservation m.DocumentUploadReservation) (m.DocumentImportAcceptanceFacts, error) {
	var facts m.DocumentImportAcceptanceFacts
	err := s.importTx(ctx, a, func(ctx context.Context, tx pgx.Tx) error {
		var err error
		facts.Path, err = lockImportPart(ctx, tx, a)
		if err != nil {
			return err
		}
		if err = importReservation(ctx, tx, a, reservation.ID); err != nil {
			return err
		}
		ref, err := uploadReference(ctx, tx, reservation.ID)
		facts.Reference = m.DocumentFileReference{AccountID: ref.AccountID, UploaderID: ref.UploaderID, DocumentID: ref.DocumentID, Location: ref.Location, File: m.DocumentFile(ref.File)}
		return err
	})
	return facts, err
}
func (s *DocumentDataSource) AcceptImport(ctx context.Context, a m.DocumentImportAuthority, reservation m.DocumentUploadReservation, command m.DocumentImportAcceptanceCommand) (m.DocumentImportResult, error) {
	result := m.DocumentImportResult{}
	metadata := command.Metadata
	err := s.importTx(ctx, a, func(ctx context.Context, tx pgx.Tx) error {
		configuration, err := prepareGeneration(ctx, tx)
		if err != nil {
			return err
		}
		path, err := lockImportPart(ctx, tx, a)
		if err != nil {
			return err
		}
		if err = importReservation(ctx, tx, a, reservation.ID); err != nil {
			return err
		}
		reference, err := uploadReference(ctx, tx, reservation.ID)
		if err != nil {
			return err
		}
		if path != command.Expected.Path || reference.File.SHA256 != command.Expected.Reference.File.SHA256 || reference.File.MediaType != command.Expected.Reference.File.MediaType || reference.File.Size != command.Expected.Reference.File.Size || reference.File.OriginalFilename != command.Expected.Reference.File.OriginalFilename {
			return m.ErrConflict
		}

		var existing string
		findExisting := func() error {
			return tx.QueryRow(ctx, `SELECT d.id FROM documents d JOIN document_files f ON f.account_id=d.account_id AND f.document_id=d.id WHERE d.account_id=$1 AND f.sha256=$2 FOR UPDATE OF d`, a.AccountID, reference.File.SHA256).Scan(&existing)
		}
		err = findExisting()
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		if errors.Is(err, pgx.ErrNoRows) {
			snapshot, err := json.Marshal(configuration)
			if err != nil {
				return err
			}
			err = pgx.BeginFunc(ctx, tx, func(created pgx.Tx) error {
				_, err := created.Exec(ctx, `INSERT INTO documents(id,account_id,title,description,created_at,kind,tags,sender,recipients,cc,bcc,document_date,subject,message_id) VALUES($1,$2,$3,$4,clock_timestamp(),$5,$6,$7,$8,$9,$10,NULLIF($11,'')::date,$12,$13)`, reservation.ID, a.AccountID, metadata.Title, metadata.Description, metadata.Kind, metadata.Tags, metadata.Sender, metadata.Recipients, metadata.CC, metadata.BCC, metadata.DocumentDate, metadata.Subject, metadata.MessageID)
				if err != nil {
					return err
				}
				if _, err = created.Exec(ctx, `INSERT INTO document_files(document_id,account_id,uploader_id,original_filename,media_type,size,sha256,ingested_at) SELECT id,account_id,uploader_id,original_filename,media_type,size,sha256,clock_timestamp() FROM document_uploads WHERE id=$1`, reservation.ID); err != nil {
					return err
				}
				if _, err = created.Exec(ctx, `INSERT INTO document_processing(document_id,account_id,generation,state,stage,configuration_revision,configuration,updated_at,delivery_deadline,initiated_by_user_id) VALUES($1,$2,1,$6,$7,$3,$4,clock_timestamp(),NULL,$5)`, reservation.ID, a.AccountID, configuration.Revision, snapshot, a.OwnerID, command.ProcessingState, command.ProcessingStage); err != nil {
					return err
				}
				if err = insertOutbox(ctx, created, m.DocumentJob{AccountID: a.AccountID, DocumentID: reservation.ID, Generation: 1}, configuration); err != nil {
					return err
				}
				_, err = created.Exec(ctx, `UPDATE document_uploads SET state='accepted' WHERE id=$1`, reservation.ID)
				return err
			})
			if errors.Is(documentError(err), m.ErrDuplicate) {
				if err = findExisting(); err != nil {
					return err
				}
			} else if err != nil {
				return err
			} else {
				result.DocumentID = reservation.ID
			}
		}
		if existing != "" {
			result = m.DocumentImportResult{DocumentID: existing, Reused: true}
			if _, err = tx.Exec(ctx, `UPDATE document_uploads SET state='reaping',expires_at=clock_timestamp() WHERE id=$1`, reservation.ID); err != nil {
				return err
			}
		}
		outcome := command.Created
		if result.Reused {
			outcome = command.Reused
		}
		if _, err = tx.Exec(ctx, "UPDATE email_parts SET state=$2,document_id=$3,failure_code=NULL,last_counted_run_id=$4,updated_at=clock_timestamp() WHERE id=$1", a.PartID, outcome.State, result.DocumentID, a.RunID); err != nil {
			return err
		}
		if outcome.Parent {
			if _, err = tx.Exec(ctx, "UPDATE email_messages SET state=$2,parent_document_id=$3,last_counted_run_id=$4,updated_at=clock_timestamp() WHERE id=$1", a.MessageID, outcome.State, result.DocumentID, a.RunID); err != nil {
				return err
			}
		}
		_, err = tx.Exec(ctx, "UPDATE email_runs SET messages_accepted=messages_accepted+$2,messages_reused=messages_reused+$3,attachments_accepted=attachments_accepted+$4,attachments_reused=attachments_reused+$5 WHERE id=$1", a.RunID, outcome.MessagesAccepted, outcome.MessagesReused, outcome.AttachmentsAccepted, outcome.AttachmentsReused)

		return err
	})
	return result, err
}
func (s *DocumentDataSource) ImportReference(ctx context.Context, a m.DocumentImportAuthority) (m.DocumentFileReference, error) {
	var result m.DocumentFileReference
	err := s.importTx(ctx, a, func(ctx context.Context, tx pgx.Tx) error {
		if _, err := lockImportPart(ctx, tx, a); err != nil {
			return err
		}
		var parent string
		if err := tx.QueryRow(ctx, `SELECT parent_document_id::text FROM email_messages WHERE id=$1 AND parent_document_id IS NOT NULL`, a.MessageID).Scan(&parent); err != nil {
			return m.ErrNotFound
		}
		reference, err := fileReference(ctx, tx, a.AccountID, parent)
		result = m.DocumentFileReference{AccountID: reference.AccountID, UploaderID: reference.UploaderID, DocumentID: reference.DocumentID, Location: reference.Location, File: m.DocumentFile(reference.File)}
		return err
	})
	return result, err
}
