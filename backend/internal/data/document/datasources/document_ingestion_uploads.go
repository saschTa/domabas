package datasources

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (s *DocumentDataSource) ReserveRecord(ctx context.Context, a m.DocumentActor, input m.DocumentUploadReservation) (r.DocumentReservationRecord, error) {
	err := s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, "INSERT INTO document_uploads(id,account_id,uploader_id,expires_at) VALUES($1,$2,$3,$4)", input.ID, a.AccountID, a.UserID, input.ExpiresAt)
		if err != nil {
			return err
		}
		return tx.QueryRow(ctx, "SELECT expires_at FROM document_uploads WHERE id=$1", input.ID).Scan(&input.ExpiresAt)
	})
	return r.DocumentReservationRecord(input), err
}
func readReservation(ctx context.Context, tx pgx.Tx, a m.DocumentActor, id string, lock bool) (r.DocumentReservationRecord, error) {
	var result r.DocumentReservationRecord
	var state string
	var alive bool
	suffix := ""
	if lock {
		suffix = " FOR UPDATE"
	}
	err := tx.QueryRow(ctx, "SELECT id,account_id,uploader_id,expires_at,state,expires_at>clock_timestamp() FROM document_uploads WHERE id=$1 AND account_id=$2 AND uploader_id=$3"+suffix, id, a.AccountID, a.UserID).Scan(&result.ID, &result.AccountID, &result.UploaderID, &result.ExpiresAt, &state, &alive)
	if err != nil {
		return result, documentError(err)
	}
	if state != "receiving" || !alive {
		return result, m.ErrConflict
	}
	return result, nil
}
func reservation(ctx context.Context, tx pgx.Tx, a m.DocumentActor, id string) (r.DocumentReservationRecord, error) {
	return readReservation(ctx, tx, a, id, true)
}
func (s *DocumentDataSource) ReservationRecord(ctx context.Context, a m.DocumentActor, id string) (r.DocumentReservationRecord, error) {
	var result r.DocumentReservationRecord
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error { var err error; result, err = readReservation(ctx, tx, a, id, false); return err })
	return result, err
}
func (s *DocumentDataSource) RecordStaged(ctx context.Context, a m.DocumentActor, id string, ref m.DocumentFileReference) error {
	return s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		current, err := reservation(ctx, tx, a, id)
		if err != nil {
			return err
		}
		if ref.DocumentID != current.ID || ref.AccountID != current.AccountID || ref.UploaderID != current.UploaderID || ref.Location != "staged" {
			return m.ErrConflict
		}
		tag, err := tx.Exec(ctx, "UPDATE document_uploads SET original_filename=$2,media_type=$3,size=$4,sha256=$5 WHERE id=$1 AND sha256 IS NULL", id, ref.File.OriginalFilename, ref.File.MediaType, ref.File.Size, ref.File.SHA256)
		if err == nil && tag.RowsAffected() != 1 {
			return m.ErrConflict
		}
		return err
	})
}
func insertOutbox(ctx context.Context, tx pgx.Tx, j m.DocumentJob, c m.DocumentProcessingConfiguration) error {
	_, err := tx.Exec(ctx, "INSERT INTO document_outbox(id,account_id,document_id,generation,configuration_revision,delivery_deadline) SELECT $1,account_id,document_id,generation,configuration_revision,delivery_deadline FROM document_processing WHERE account_id=$2 AND document_id=$3 AND generation=$4", uuid.NewString(), j.AccountID, j.DocumentID, j.Generation)
	return err
}
func readUploadAcceptanceFacts(ctx context.Context, tx pgx.Tx, a m.DocumentActor, id string) (m.DocumentUploadAcceptanceFacts, error) {
	var facts m.DocumentUploadAcceptanceFacts
	if err := tx.QueryRow(ctx, "SELECT state,expires_at FROM document_uploads WHERE id=$1 AND account_id=$2 AND uploader_id=$3", id, a.AccountID, a.UserID).Scan(&facts.State, &facts.ExpiresAt); err != nil {
		return facts, err
	}
	reference, err := uploadReference(ctx, tx, id)
	facts.Reference = m.DocumentFileReference{AccountID: reference.AccountID, UploaderID: reference.UploaderID, DocumentID: reference.DocumentID, Location: reference.Location, File: m.DocumentFile(reference.File)}
	return facts, err
}
func (s *DocumentDataSource) UploadAcceptanceFacts(ctx context.Context, a m.DocumentActor, id string) (m.DocumentUploadAcceptanceFacts, error) {
	var facts m.DocumentUploadAcceptanceFacts
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var err error
		facts, err = readUploadAcceptanceFacts(ctx, tx, a, id)
		return err
	})
	return facts, err
}
func (s *DocumentDataSource) AcceptRecord(ctx context.Context, a m.DocumentActor, id string, command m.DocumentUploadAcceptanceCommand) (r.DocumentRecord, error) {
	var result r.DocumentRecord
	metadata, stamp := command.Metadata, command.CreatedAt
	err := s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		c, err := prepareGeneration(ctx, tx)
		if err != nil {
			return err
		}
		if _, err := reservation(ctx, tx, a, id); err != nil {
			return err
		}
		facts, err := readUploadAcceptanceFacts(ctx, tx, a, id)
		if err != nil {
			return err
		}
		if !reflect.DeepEqual(facts, command.Expected) {
			return m.ErrConflict
		}

		snapshot, err := json.Marshal(c)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO documents(id,account_id,title,description,created_at,kind,tags,sender,recipients,cc,bcc,document_date,subject,message_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,NULLIF($12,'')::date,$13,$14)`, id, a.AccountID, metadata.Title, metadata.Description, stamp, metadata.Kind, metadata.Tags, metadata.Sender, metadata.Recipients, metadata.CC, metadata.BCC, metadata.DocumentDate, metadata.Subject, metadata.MessageID)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO document_files(document_id,account_id,uploader_id,original_filename,media_type,size,sha256,ingested_at) SELECT id,account_id,uploader_id,original_filename,media_type,size,sha256,$2 FROM document_uploads WHERE id=$1`, id, stamp)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO document_processing(document_id,account_id,generation,state,stage,configuration_revision,configuration,updated_at,delivery_deadline,initiated_by_user_id) VALUES($1,$2,1,$6,$7,$3,$4,clock_timestamp(),NULL,$5)`, id, a.AccountID, c.Revision, snapshot, a.UserID, command.ProcessingState, command.ProcessingStage)
		if err != nil {
			return err
		}
		if err = insertOutbox(ctx, tx, m.DocumentJob{AccountID: a.AccountID, DocumentID: id, Generation: 1}, c); err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, "UPDATE document_uploads SET state=$2 WHERE id=$1", id, command.ReservationState); err != nil {
			return err
		}
		result, err = readDocument(ctx, tx, a.AccountID, id)
		return err
	})
	return result, err
}
func uploadReference(ctx context.Context, tx pgx.Tx, id string) (r.DocumentReferenceRecord, error) {
	var ref r.DocumentReferenceRecord
	ref.Location = "staged"
	err := tx.QueryRow(ctx, `SELECT account_id,uploader_id,id,COALESCE(original_filename,''),COALESCE(media_type,''),COALESCE(size,0),COALESCE(sha256,'') FROM document_uploads WHERE id=$1`, id).Scan(&ref.AccountID, &ref.UploaderID, &ref.DocumentID, &ref.File.OriginalFilename, &ref.File.MediaType, &ref.File.Size, &ref.File.SHA256)
	ref.File.UploaderID = ref.UploaderID
	return ref, err
}
func (s *DocumentDataSource) AbandonRecord(ctx context.Context, a m.DocumentActor, id string) (*r.DocumentReferenceRecord, error) {
	var result *r.DocumentReferenceRecord
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		var current string
		err := tx.QueryRow(ctx, "SELECT id FROM document_uploads WHERE id=$1 AND account_id=$2 AND uploader_id=$3 AND state IN ('receiving','reaping') AND NOT EXISTS(SELECT 1 FROM document_files f WHERE f.document_id=document_uploads.id) FOR UPDATE", id, a.AccountID, a.UserID).Scan(&current)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, "UPDATE document_uploads SET state='reaping' WHERE id=$1", id); err != nil {
			return err
		}
		ref, err := uploadReference(ctx, tx, id)
		result = &ref
		return err
	})
	return result, err
}
func (s *DocumentDataSource) ReapRecords(ctx context.Context, policy m.DocumentUploadRetentionPolicy) ([]r.DocumentReferenceRecord, error) {
	result := []r.DocumentReferenceRecord{}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `WITH claimed AS(
 SELECT u.id FROM document_uploads u WHERE
 (u.state=ANY($2::text[]) AND u.expires_at<=clock_timestamp())
 OR (u.state=$3 AND EXISTS(SELECT 1 FROM document_files f JOIN document_processing p ON p.document_id=f.document_id AND p.account_id=f.account_id WHERE f.document_id=u.id AND f.account_id=u.account_id AND f.location=ANY($4::text[]) AND p.state=$5))
 ORDER BY u.expires_at,u.id LIMIT $1 FOR UPDATE OF u SKIP LOCKED)
 UPDATE document_uploads u SET state=CASE WHEN u.state IN ($3,$6) THEN $6 ELSE $7 END,expires_at=clock_timestamp()+$8::interval
 FROM claimed c WHERE u.id=c.id RETURNING u.id`, policy.Limit, policy.ExpiredStates, policy.AcceptedState, policy.DurableLocations, policy.ReadyState, policy.RetiringState, policy.ReapingState, policy.ClaimLease.String())
		if err != nil {
			return err
		}
		ids := []string{}
		for rows.Next() {
			var id string
			if err = rows.Scan(&id); err != nil {
				rows.Close()
				return err
			}
			ids = append(ids, id)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return err
		}
		for _, id := range ids {
			ref, err := uploadReference(ctx, tx, id)
			if err != nil {
				return err
			}
			result = append(result, ref)
		}
		return nil
	})
	return result, err
}
func (s *DocumentDataSource) Reaped(ctx context.Context, ref m.DocumentFileReference, policy m.DocumentUploadRetentionPolicy) error {
	var count int
	err := s.database.QueryRow(ctx, `WITH deleted AS(DELETE FROM document_uploads u WHERE id=$1 AND account_id=$2 AND uploader_id=$3 AND (
 (state=$4 AND NOT EXISTS(SELECT 1 FROM document_files WHERE document_id=$1))
 OR (state=$5 AND EXISTS(SELECT 1 FROM document_files f JOIN document_processing p ON p.document_id=f.document_id AND p.account_id=f.account_id WHERE f.document_id=u.id AND f.account_id=u.account_id AND f.location=ANY($6::text[]) AND p.state=$7))
 ) RETURNING id) SELECT count(*) FROM deleted`, ref.DocumentID, ref.AccountID, ref.UploaderID, policy.ReapingState, policy.RetiringState, policy.DurableLocations, policy.ReadyState).Scan(&count)
	return err
}
