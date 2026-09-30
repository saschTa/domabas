package datasources

import (
	"context"
	"errors"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func cursorRow(ctx context.Context, tx pgx.Tx, work m.EmailWork) (m.EmailCursor, error) {
	var c m.EmailCursor
	err := tx.QueryRow(ctx, `SELECT mailbox_generation,live_next_uid,COALESCE(live_upper_uid,0),COALESCE(backfill_next_uid,0),COALESCE(backfill_upper_uid,0),discovery_backfill_next,retry_next FROM email_mailboxes WHERE provider_id=$1 AND source_generation=$2 FOR UPDATE`, work.Provider.ID, work.Provider.SourceGeneration).Scan(&c.MailboxGeneration, &c.LiveNext, &c.LiveUpper, &c.BackfillNext, &c.BackfillUpper, &c.BackfillTurn, &c.RetryTurn)
	return c, err
}
func (s *EmailDataSource) MailboxFacts(ctx context.Context, attempt m.EmailAttempt) (m.EmailMailboxFacts, error) {
	var facts m.EmailMailboxFacts
	err := s.attemptTx(ctx, attempt, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		facts.ProviderMaxAgeDays = work.Provider.MaxAgeDays
		err := tx.QueryRow(ctx, `SELECT uid_validity,max_age_days,mailbox_generation,live_next_uid,COALESCE(live_upper_uid,0),COALESCE(backfill_next_uid,0),COALESCE(backfill_upper_uid,0),discovery_backfill_next,retry_next FROM email_mailboxes WHERE provider_id=$1 AND source_generation=$2`, work.Provider.ID, work.Provider.SourceGeneration).Scan(&facts.UIDValidity, &facts.MaxAgeDays, &facts.Cursor.MailboxGeneration, &facts.Cursor.LiveNext, &facts.Cursor.LiveUpper, &facts.Cursor.BackfillNext, &facts.Cursor.BackfillUpper, &facts.Cursor.BackfillTurn, &facts.Cursor.RetryTurn)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		facts.Exists = err == nil
		return err
	})
	return facts, err
}
func (s *EmailDataSource) SetupMailbox(ctx context.Context, attempt m.EmailAttempt, command m.EmailMailboxCommand) (m.EmailCursor, error) {
	err := s.attemptTx(ctx, attempt, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		if !command.Expected.Exists {
			tag, err := tx.Exec(ctx, `INSERT INTO email_mailboxes(provider_id,source_generation,uid_validity,max_age_days) VALUES($1,$2,$3,$4) ON CONFLICT(provider_id,source_generation) DO NOTHING`, work.Provider.ID, work.Provider.SourceGeneration, command.UIDValidity, command.MaxAgeDays)
			if err != nil {
				return err
			}
			if tag.RowsAffected() != 1 {
				return m.ErrConflict
			}
		} else {
			current, err := cursorRow(ctx, tx, work)
			if err != nil {
				return err
			}
			var validity int64
			var age int
			if err = tx.QueryRow(ctx, "SELECT uid_validity,max_age_days FROM email_mailboxes WHERE provider_id=$1 AND source_generation=$2", work.Provider.ID, work.Provider.SourceGeneration).Scan(&validity, &age); err != nil {
				return err
			}
			if current != command.Expected.Cursor || validity != command.Expected.UIDValidity || age != command.Expected.MaxAgeDays {
				return m.ErrConflict
			}
		}
		next := command.Cursor
		_, err := tx.Exec(ctx, `UPDATE email_mailboxes SET mailbox_generation=$3,uid_validity=$4,live_next_uid=$5,live_upper_uid=$6,backfill_next_uid=NULLIF($7,0),backfill_upper_uid=NULLIF($8,0),max_age_days=$9,discovery_backfill_next=$10,retry_next=$11 WHERE provider_id=$1 AND source_generation=$2`, work.Provider.ID, work.Provider.SourceGeneration, next.MailboxGeneration, command.UIDValidity, next.LiveNext, next.LiveUpper, next.BackfillNext, next.BackfillUpper, command.MaxAgeDays, next.BackfillTurn, command.NextRetryTurn)
		if err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, "UPDATE email_runs SET mailbox_generation=$2 WHERE id=$1", attempt.RunID, next.MailboxGeneration); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `WITH old AS(SELECT id FROM email_messages WHERE provider_id=$1 AND (source_generation<>$2 OR mailbox_generation<>$3) AND (state='pending' OR inspection_state='pending' OR pending_parts) ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED) UPDATE email_messages m SET state=CASE WHEN parent_document_id IS NULL THEN $4 ELSE state END,failure_code=CASE WHEN source_generation<>$2 THEN 'source_changed' ELSE 'mailbox_changed' END,inspection_state=$5,pending_parts=false,attempt_token=NULL,updated_at=clock_timestamp() FROM old WHERE m.id=old.id`, work.Provider.ID, work.Provider.SourceGeneration, command.Cursor.MailboxGeneration, command.ObsoleteMessageState, command.ObsoleteInspectionState)
		if err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, `WITH old AS(SELECT p.id,m.source_generation FROM email_parts p JOIN email_messages m ON m.id=p.message_id WHERE m.provider_id=$1 AND (m.source_generation<>$2 OR m.mailbox_generation<>$3) AND p.state='pending' ORDER BY p.id LIMIT 100 FOR UPDATE OF p SKIP LOCKED) UPDATE email_parts p SET state=$4,failure_code=CASE WHEN old.source_generation<>$2 THEN 'source_changed' ELSE 'mailbox_changed' END,attempt_token=NULL,updated_at=clock_timestamp() FROM old WHERE p.id=old.id`, work.Provider.ID, work.Provider.SourceGeneration, command.Cursor.MailboxGeneration, command.ObsoletePartState); err != nil {
			return err
		}
		if command.ReviveExcluded {
			_, err = tx.Exec(ctx, `WITH candidates AS(SELECT id FROM email_messages WHERE provider_id=$1 AND source_generation=$2 AND mailbox_generation=$3 AND state='skipped' AND failure_code='age_excluded' AND internal_date>=clock_timestamp()-make_interval(days=>$4) ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED) UPDATE email_messages m SET state='pending',failure_code=NULL,next_attempt_at=clock_timestamp() FROM candidates c WHERE m.id=c.id`, work.Provider.ID, work.Provider.SourceGeneration, command.Cursor.MailboxGeneration, command.MaxAgeDays)
		}
		return err
	})
	return command.Cursor, err
}

const itemColumns = `id::text,run_id::text,provider_id::text,account_id::text,owner_id::text,state,COALESCE(parent_document_id::text,''),inspection_state,provider_revision,source_generation,mailbox_generation,uid,COALESCE(internal_date,'epoch'::timestamptz)`

func scanItem(row emailRowScanner) (m.EmailItem, error) {
	var item m.EmailItem
	err := row.Scan(&item.ID, &item.RunID, &item.ProviderID, &item.AccountID, &item.OwnerID, &item.State, &item.ParentDocumentID, &item.InspectionState, &item.ProviderRevision, &item.SourceGeneration, &item.MailboxGeneration, &item.UID, &item.InternalDate)
	return item, err
}
func bindItem(ctx context.Context, tx pgx.Tx, work m.EmailWork, id string) (m.EmailItem, error) {
	return scanItem(tx.QueryRow(ctx, `UPDATE email_messages SET run_id=$2,provider_revision=$3,attempt_token=$4,last_attempt_at=clock_timestamp() WHERE id=$1 AND provider_id=$5 AND source_generation=$6 AND mailbox_generation=$7 AND next_attempt_at<=clock_timestamp() AND (state='pending' OR (state IN ('accepted','reused') AND (inspection_state='pending' OR pending_parts))) RETURNING `+itemColumns, id, work.Run.ID, work.Provider.Revision, work.Attempt.Token, work.Provider.ID, work.Provider.SourceGeneration, work.Run.MailboxGeneration))
}
func (s *EmailDataSource) PendingItems(ctx context.Context, attempt m.EmailAttempt, query m.EmailPendingQuery) ([]m.EmailItem, error) {
	result := []m.EmailItem{}
	if query.Limit == 0 {
		return result, nil
	}
	err := s.attemptTx(ctx, attempt, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		if _, err := tx.Exec(ctx, `WITH excluded AS(SELECT id FROM email_messages WHERE provider_id=$1 AND source_generation=$2 AND mailbox_generation=$3 AND state='pending' AND parent_document_id IS NULL AND internal_date<$4 ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED) UPDATE email_messages m SET state=$5,failure_code=$6,inspection_state=$7,pending_parts=false FROM excluded e WHERE m.id=e.id`, work.Provider.ID, work.Provider.SourceGeneration, work.Run.MailboxGeneration, query.Cutoff, query.ExcludedState, query.FailureCode, query.InspectionState); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT id::text FROM email_messages WHERE provider_id=$1 AND source_generation=$2 AND mailbox_generation=$3 AND next_attempt_at<=clock_timestamp() AND (state='pending' OR (state IN ('accepted','reused') AND (inspection_state='pending' OR pending_parts))) ORDER BY next_attempt_at,last_attempt_at,id LIMIT $4 FOR UPDATE SKIP LOCKED`, work.Provider.ID, work.Provider.SourceGeneration, work.Run.MailboxGeneration, query.Limit)
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
			item, err := bindItem(ctx, tx, work, id)
			if err != nil {
				return err
			}
			result = append(result, item)
		}
		return nil
	})
	return result, err
}
func (s *EmailDataSource) DiscoverItems(ctx context.Context, attempt m.EmailAttempt, command m.EmailDiscoveryCommand) ([]m.EmailItem, error) {
	result := []m.EmailItem{}
	err := s.attemptTx(ctx, attempt, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		c, err := cursorRow(ctx, tx, work)
		if err != nil {
			return err
		}
		if c != command.Expected {
			return m.ErrStaleAttempt
		}
		discovered := int64(0)
		for _, uid := range command.UIDs {
			id := uuid.NewString()
			tag, err := tx.Exec(ctx, `INSERT INTO email_messages(id,provider_id,account_id,owner_id,source_generation,mailbox_generation,uid,run_id,provider_revision,attempt_token) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(provider_id,source_generation,mailbox_generation,uid) DO NOTHING`, id, work.Provider.ID, work.Provider.AccountID, work.Provider.OwnerID, work.Provider.SourceGeneration, work.Run.MailboxGeneration, uid, work.Run.ID, work.Provider.Revision, attempt.Token)
			if err != nil {
				return err
			}
			discovered += tag.RowsAffected()
			if err = tx.QueryRow(ctx, `SELECT id::text FROM email_messages WHERE provider_id=$1 AND source_generation=$2 AND mailbox_generation=$3 AND uid=$4`, work.Provider.ID, work.Provider.SourceGeneration, work.Run.MailboxGeneration, uid).Scan(&id); err != nil {
				return err
			}
			if command.ReviveExcluded {
				if _, err = tx.Exec(ctx, `UPDATE email_messages SET state='pending',failure_code=NULL,inspection_state='pending',next_attempt_at=clock_timestamp() WHERE id=$1 AND parent_document_id IS NULL AND state='skipped' AND failure_code='age_excluded' AND internal_date>=clock_timestamp()-make_interval(days=>$2)`, id, command.MaxAgeDays); err != nil {
					return err
				}
			}
			item, err := bindItem(ctx, tx, work, id)
			if errors.Is(err, pgx.ErrNoRows) {
				continue
			}
			if err != nil {
				return err
			}
			result = append(result, item)
		}
		next := command.Next
		_, err = tx.Exec(ctx, `UPDATE email_mailboxes SET live_next_uid=$3,backfill_next_uid=NULLIF($4,0),backfill_upper_uid=NULLIF($5,0),discovery_backfill_next=$6 WHERE provider_id=$1 AND source_generation=$2`, work.Provider.ID, work.Provider.SourceGeneration, next.LiveNext, next.BackfillNext, next.BackfillUpper, next.BackfillTurn)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE email_runs SET messages_discovered=messages_discovered+$2 WHERE id=$1`, attempt.RunID, discovered)
		return err
	})
	return result, err
}
func verifyItem(ctx context.Context, tx pgx.Tx, work m.EmailWork, item m.EmailItem) error {
	var id string
	err := tx.QueryRow(ctx, `SELECT id FROM email_messages WHERE id=$1 AND provider_id=$2 AND source_generation=$3 AND mailbox_generation=$4 AND run_id=$5 AND provider_revision=$6 AND attempt_token=$7 FOR UPDATE`, item.ID, work.Provider.ID, work.Provider.SourceGeneration, work.Run.MailboxGeneration, work.Run.ID, work.Provider.Revision, work.Attempt.Token).Scan(&id)
	if err != nil {
		return m.ErrStaleAttempt
	}
	return nil
}
func (s *EmailDataSource) Part(ctx context.Context, attempt m.EmailAttempt, item m.EmailItem, path, filename, media string) (m.EmailPart, error) {
	result := m.EmailPart{}
	err := s.attemptTx(ctx, attempt, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		if err := verifyItem(ctx, tx, work, item); err != nil {
			return err
		}
		err := tx.QueryRow(ctx, `INSERT INTO email_parts(id,message_id,account_id,path,filename,media_type,attempt_token) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(message_id,path) DO UPDATE SET attempt_token=EXCLUDED.attempt_token,reservation_id=CASE WHEN email_parts.attempt_token IS DISTINCT FROM EXCLUDED.attempt_token THEN NULL ELSE email_parts.reservation_id END RETURNING id::text,message_id::text,path,filename,state,COALESCE(failure_code,''),COALESCE(document_id::text,'')`, uuid.NewString(), item.ID, work.Provider.AccountID, path, filename, media, attempt.Token).Scan(&result.ID, &result.MessageID, &result.Path, &result.Filename, &result.State, &result.FailureCode, &result.DocumentID)
		return err
	})
	return result, err
}
func emailPartFacts(ctx context.Context, tx pgx.Tx, attempt m.EmailAttempt, item m.EmailItem, part m.EmailPart) (m.EmailPartFacts, error) {
	var facts m.EmailPartFacts
	err := tx.QueryRow(ctx, `SELECT path,COALESCE(last_counted_run_id::text,''),state FROM email_parts WHERE id=$1 AND message_id=$2 AND attempt_token=$3 AND document_id IS NULL FOR UPDATE`, part.ID, item.ID, attempt.Token).Scan(&facts.Path, &facts.LastCountedRunID, &facts.State)
	if errors.Is(err, pgx.ErrNoRows) {
		return facts, m.ErrStaleAttempt
	}
	return facts, err
}
func (s *EmailDataSource) PartFacts(ctx context.Context, a m.EmailAttempt, item m.EmailItem, part m.EmailPart) (m.EmailPartFacts, error) {
	var facts m.EmailPartFacts
	err := s.attemptTx(ctx, a, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		if err := verifyItem(ctx, tx, work, item); err != nil {
			return err
		}
		var err error
		facts, err = emailPartFacts(ctx, tx, a, item, part)
		return err
	})
	return facts, err
}
func (s *EmailDataSource) PartOutcome(ctx context.Context, a m.EmailAttempt, item m.EmailItem, part m.EmailPart, command m.EmailPartOutcomeCommand) error {
	return s.attemptTx(ctx, a, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		if err := verifyItem(ctx, tx, work, item); err != nil {
			return err
		}
		facts, err := emailPartFacts(ctx, tx, a, item, part)
		if err != nil {
			return err
		}
		if facts != command.Expected {
			return m.ErrConflict
		}
		if _, err = tx.Exec(ctx, `UPDATE email_parts SET state=$2,failure_code=NULLIF($3,''),last_counted_run_id=$4,updated_at=clock_timestamp() WHERE id=$1`, part.ID, command.State, command.Code, a.RunID); err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, `UPDATE email_runs SET attachments_failed=attachments_failed+$2,attachments_skipped=attachments_skipped+$3 WHERE id=$1`, a.RunID, command.Failed, command.Skipped); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE email_messages SET pending_parts=EXISTS(SELECT 1 FROM email_parts WHERE message_id=$1 AND path<>'0' AND state='pending'),content_failure=content_failure OR $2 WHERE id=$1`, item.ID, command.ContentFailure)
		return err
	})
}
func emailMessageFacts(ctx context.Context, tx pgx.Tx, item m.EmailItem) (m.EmailMessageFacts, error) {
	var facts m.EmailMessageFacts
	err := tx.QueryRow(ctx, `SELECT state,COALESCE(parent_document_id::text,''),COALESCE(last_counted_run_id::text,''),inspection_state,pending_parts,retry_count FROM email_messages WHERE id=$1`, item.ID).Scan(&facts.State, &facts.ParentDocumentID, &facts.LastCountedRunID, &facts.InspectionState, &facts.PendingParts, &facts.RetryCount)
	return facts, err
}
func (s *EmailDataSource) MessageFacts(ctx context.Context, a m.EmailAttempt, item m.EmailItem) (m.EmailMessageFacts, error) {
	var facts m.EmailMessageFacts
	err := s.attemptTx(ctx, a, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		if err := verifyItem(ctx, tx, work, item); err != nil {
			return err
		}
		var err error
		facts, err = emailMessageFacts(ctx, tx, item)
		return err
	})
	return facts, err
}
func (s *EmailDataSource) MessageOutcome(ctx context.Context, a m.EmailAttempt, item m.EmailItem, command m.EmailMessageOutcomeCommand) error {
	return s.attemptTx(ctx, a, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		if err := verifyItem(ctx, tx, work, item); err != nil {
			return err
		}
		facts, err := emailMessageFacts(ctx, tx, item)
		if err != nil {
			return err
		}
		if facts != command.Expected {
			return m.ErrConflict
		}
		if command.DateOnly {
			_, err = tx.Exec(ctx, `UPDATE email_messages SET internal_date=$2 WHERE id=$1`, item.ID, command.InternalDate)
			return err
		}
		if _, err = tx.Exec(ctx, `UPDATE email_runs SET messages_failed=messages_failed+$2,messages_skipped=messages_skipped+$3 WHERE id=$1`, a.RunID, command.Failed, command.Skipped); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE email_messages SET state=$2,failure_code=NULLIF($3,''),internal_date=COALESCE($4,internal_date),inspection_state=$5,pending_parts=$6,last_counted_run_id=$7,retry_count=retry_count+1,next_attempt_at=clock_timestamp()+$8::interval,updated_at=clock_timestamp() WHERE id=$1`, item.ID, command.State, command.Code, command.InternalDate, command.InspectionState, command.PendingParts, a.RunID, command.RetryDelay.String())
		return err
	})
}
func (s *EmailDataSource) InspectionOutcome(ctx context.Context, a m.EmailAttempt, item m.EmailItem, command m.EmailInspectionCommand) error {
	return s.attemptTx(ctx, a, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		if err := verifyItem(ctx, tx, work, item); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE email_messages SET inspection_state=$2,content_failure=content_failure OR $3,pending_parts=EXISTS(SELECT 1 FROM email_parts WHERE message_id=$1 AND path<>'0' AND state='pending'),updated_at=clock_timestamp() WHERE id=$1`, item.ID, command.State, command.ContentFailure); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE email_runs SET messages_with_content_failures=(SELECT count(*) FROM email_messages WHERE run_id=$1 AND parent_document_id IS NOT NULL AND content_failure) WHERE id=$1`, a.RunID)
		return err
	})
}
func (s *EmailDataSource) HasMore(ctx context.Context, attempt m.EmailAttempt) (bool, error) {
	result := false
	err := s.attemptTx(ctx, attempt, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		return tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM email_mailboxes WHERE provider_id=$1 AND source_generation=$2 AND (live_next_uid<=live_upper_uid OR backfill_next_uid<=backfill_upper_uid)) OR EXISTS(SELECT 1 FROM email_messages WHERE provider_id=$1 AND source_generation=$2 AND mailbox_generation=$3 AND next_attempt_at<=clock_timestamp() AND (state='pending' OR state IN ('accepted','reused') AND (inspection_state='pending' OR pending_parts)))`, work.Provider.ID, work.Provider.SourceGeneration, work.Run.MailboxGeneration).Scan(&result)
	})
	return result, err
}
