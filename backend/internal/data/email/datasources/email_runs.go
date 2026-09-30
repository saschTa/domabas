package datasources

import (
	"context"
	"errors"
	"slices"

	r "github.com/domabas/domabas/backend/internal/data/email/models"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const runColumns = `id::text,provider_id::text,account_id::text,owner_id::text,provider_revision,source_generation,mailbox_generation,trigger,COALESCE(request_id::text,''),status,stage,COALESCE(failure_code,''),messages_discovered,messages_accepted,messages_reused,messages_skipped,messages_failed,messages_with_content_failures,attachments_accepted,attachments_reused,attachments_skipped,attachments_failed,has_more,created_at,started_at,finished_at`

func scanRun(row emailRowScanner) (m.EmailRun, error) {
	var r m.EmailRun
	err := row.Scan(&r.ID, &r.ProviderID, &r.AccountID, &r.OwnerID, &r.ProviderRevision, &r.SourceGeneration, &r.MailboxGeneration, &r.Trigger, &r.RequestID, &r.Status, &r.Stage, &r.FailureCode, &r.MessagesDiscovered, &r.MessagesAccepted, &r.MessagesReused, &r.MessagesSkipped, &r.MessagesFailed, &r.MessagesWithContentFailures, &r.AttachmentsAccepted, &r.AttachmentsReused, &r.AttachmentsSkipped, &r.AttachmentsFailed, &r.HasMore, &r.CreatedAt, &r.StartedAt, &r.FinishedAt)
	return r, err
}
func (s *EmailDataSource) Runs(ctx context.Context, a m.EmailActor, q m.EmailRunQuery) (m.EmailRunPage, error) {
	result := m.EmailRunPage{Items: []m.EmailRun{}}
	limit, id, value := q.Limit, q.ProviderID, q.Cursor
	if err := q.Validate(); err != nil {
		return result, err
	}
	kind := "runs:" + id
	if q.ActiveOnly {
		kind += ":active"
	}
	if q.Status != "" {
		kind += ":" + q.Status
	}
	c, err := decodeCursor(value, a, kind, limit)
	if err != nil {
		return result, err
	}
	err = s.readTx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		if id != "" {
			if _, err := readProvider(ctx, tx, a, id); err != nil {
				return err
			}
		}
		countRows, err := tx.Query(ctx, "SELECT status,count(*) FROM email_runs WHERE account_id=$1 AND owner_id=$2 AND ($3='' OR provider_id=NULLIF($3,'')::uuid) GROUP BY status", a.AccountID, a.UserID, id)
		if err != nil {
			return err
		}
		for countRows.Next() {
			var count m.EmailJobStatusCount
			if err = countRows.Scan(&count.Status, &count.Count); err != nil {
				countRows.Close()
				return err
			}
			result.Counts = append(result.Counts, count)
		}
		err = countRows.Err()
		countRows.Close()
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT `+runColumns+` FROM email_runs WHERE ($1='' OR provider_id=NULLIF($1,'')::uuid) AND account_id=$2 AND owner_id=$3 AND ($7='' OR status=$7) AND (NOT $8 OR status IN ('queued','running')) AND (created_at,id)<($4,$5) ORDER BY created_at DESC,id DESC LIMIT $6`, id, a.AccountID, a.UserID, c.At, c.ID, limit+1, q.Status, q.ActiveOnly)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			run, err := scanRun(rows)
			if err != nil {
				return err
			}
			result.Items = append(result.Items, run)
		}
		return rows.Err()
	})
	if len(result.Items) > limit {
		result.Items = result.Items[:limit]
		last := result.Items[len(result.Items)-1]
		result.NextCursor = encodeCursor(a, kind, last.ID, last.CreatedAt, limit)
	}
	return result, err
}
func (s *EmailDataSource) Run(ctx context.Context, a m.EmailActor, id string) (m.EmailRun, error) {
	var result m.EmailRun
	err := s.readTx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		var err error
		result, err = scanRun(tx.QueryRow(ctx, `SELECT `+runColumns+` FROM email_runs WHERE id=$1 AND account_id=$2 AND owner_id=$3`, id, a.AccountID, a.UserID))
		return err
	})
	return result, err
}
func insertRun(ctx context.Context, tx pgx.Tx, provider r.EmailProvider, trigger, request string) (m.EmailRun, error) {
	id := uuid.NewString()
	result, err := scanRun(tx.QueryRow(ctx, `INSERT INTO email_runs(id,provider_id,account_id,owner_id,provider_revision,source_generation,trigger,request_id) VALUES($1,$2,$3,$4,$5,$6,$7,NULLIF($8,'')::uuid) ON CONFLICT DO NOTHING RETURNING `+runColumns, id, provider.ID, provider.AccountID, provider.OwnerID, provider.Revision, provider.SourceGeneration, trigger, request))
	if err != nil {
		return result, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO email_outbox(run_id) VALUES($1)`, id); err != nil {
		return result, err
	}
	_, err = tx.Exec(ctx, `UPDATE email_providers SET last_run_id=$2,last_served_at=clock_timestamp(),last_failure_code=NULL WHERE id=$1`, provider.ID, id)
	return result, err
}
func (s *EmailDataSource) Start(ctx context.Context, a m.EmailActor, id string, command m.EmailStartCommand) (m.EmailRun, error) {
	input := command.Input
	var result m.EmailRun
	err := s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		provider, err := lockProvider(ctx, tx, a, id)
		if err != nil {
			return err
		}
		result, err = requestedRun(ctx, tx, a, id, input)
		if err == nil {
			return nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		expected := command.Expected
		if provider.Provider.Revision != expected.Revision || provider.Provider.Enabled != expected.Enabled || provider.Provider.ConsentRevision != expected.ConsentRevision || provider.Provider.SourceGeneration != expected.SourceGeneration || provider.Provider.CredentialVersion != expected.CredentialVersion {
			return m.ErrConflict
		}
		result, err = insertRun(ctx, tx, provider.Provider, command.Trigger, input.RequestID)
		if errors.Is(err, pgx.ErrNoRows) {
			result, err = requestedRun(ctx, tx, a, id, input)
			if errors.Is(err, pgx.ErrNoRows) {
				return m.ErrConflict
			}
		}
		return err
	})
	return result, err
}
func requestedRun(ctx context.Context, tx pgx.Tx, actor m.EmailActor, providerID string, input m.EmailStartRun) (m.EmailRun, error) {
	run, err := scanRun(tx.QueryRow(ctx, `SELECT `+runColumns+` FROM email_runs WHERE request_id=$1`, input.RequestID))
	if err != nil {
		return run, err
	}
	if run.OwnerID != actor.UserID || run.AccountID != actor.AccountID {
		return m.EmailRun{}, m.ErrNotFound
	}
	if run.ProviderID != providerID || run.ProviderRevision != input.ExpectedRevision {
		return m.EmailRun{}, m.ErrConflict
	}
	return run, nil
}
func (s *EmailDataSource) RequestedRun(ctx context.Context, a m.EmailActor, id string, input m.EmailStartRun) (*m.EmailRun, error) {
	var result *m.EmailRun
	err := s.readTx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		if _, err := readProvider(ctx, tx, a, id); err != nil {
			return err
		}
		run, err := requestedRun(ctx, tx, a, id, input)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		result = &run
		return nil
	})
	return result, err
}
func (s *EmailDataSource) ScheduleCandidates(ctx context.Context, keyIDs ...string) ([]m.EmailScheduleCandidate, error) {
	result := []m.EmailScheduleCandidate{}
	err := s.readTx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT p.id::text,p.account_id::text,p.owner_id::text,p.revision,p.source_generation,COALESCE(p.consent_revision,0),COALESCE(r.has_more,false) FROM email_providers p LEFT JOIN email_runs r ON r.id=p.last_run_id WHERE p.enabled AND p.deleted_at IS NULL AND p.next_poll_at<=clock_timestamp() AND ($1::text[] IS NULL OR p.credential_key_id=ANY($1)) AND NOT EXISTS(SELECT 1 FROM email_runs active WHERE active.provider_id=p.id AND active.status IN ('queued','running')) ORDER BY p.next_poll_at,p.last_served_at,p.id LIMIT 20`, keyIDs)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var c m.EmailScheduleCandidate
			if err = rows.Scan(&c.ProviderID, &c.AccountID, &c.OwnerID, &c.ProviderRevision, &c.SourceGeneration, &c.ConsentRevision, &c.HasMore); err != nil {
				return err
			}
			result = append(result, c)
		}
		return rows.Err()
	})
	return result, err
}
func (s *EmailDataSource) ScheduleProvider(ctx context.Context, c m.EmailScheduleCandidate, trigger string, keyIDs ...string) error {
	return s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		a := m.EmailActor{AccountID: c.AccountID, UserID: c.OwnerID, CredentialRevision: c.ConsentRevision}
		provider, err := lockProvider(ctx, tx, a, c.ProviderID)
		if err != nil {
			return err
		}
		if !provider.Provider.Enabled || provider.Provider.Revision != c.ProviderRevision || provider.Provider.SourceGeneration != c.SourceGeneration || provider.Provider.ConsentRevision != c.ConsentRevision {
			return m.ErrConflict
		}
		if keyIDs != nil && !slices.Contains(keyIDs, provider.KeyID) {
			return nil
		}
		tag, err := tx.Exec(ctx, `UPDATE email_providers SET last_served_at=clock_timestamp(),next_poll_at=clock_timestamp()+interval '30 seconds' WHERE id=$1 AND next_poll_at<=clock_timestamp()`, c.ProviderID)
		if err != nil || tag.RowsAffected() != 1 {
			return err
		}
		_, err = insertRun(ctx, tx, provider.Provider, trigger, "")
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		return err
	})
}
func (s *EmailDataSource) FinishFacts(ctx context.Context, attempt m.EmailAttempt) (m.EmailRunFinishFacts, error) {
	var facts m.EmailRunFinishFacts
	err := s.attemptTx(ctx, attempt, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		facts.Work = work
		return tx.QueryRow(ctx, "SELECT retry_count FROM email_providers WHERE id=$1", work.Provider.ID).Scan(&facts.RetryCount)
	})
	return facts, err
}
func (s *EmailDataSource) Finish(ctx context.Context, command m.EmailRunFinishCommand) error {
	attempt := command.Facts.Work.Attempt
	return s.attemptTx(ctx, attempt, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		current, expected := work.Run, command.Facts.Work.Run
		if current.Stage != expected.Stage || current.MessagesFailed != expected.MessagesFailed || current.MessagesWithContentFailures != expected.MessagesWithContentFailures || current.AttachmentsFailed != expected.AttachmentsFailed || current.MessagesAccepted != expected.MessagesAccepted || current.MessagesReused != expected.MessagesReused || current.AttachmentsAccepted != expected.AttachmentsAccepted || current.AttachmentsReused != expected.AttachmentsReused {
			return m.ErrConflict
		}
		tag, err := tx.Exec(ctx, `UPDATE email_providers SET next_poll_at=LEAST(clock_timestamp()+$2::interval,(SELECT min(next_attempt_at) FROM email_messages WHERE provider_id=$1 AND source_generation=$5 AND mailbox_generation=$6 AND next_attempt_at>clock_timestamp() AND (state='pending' OR state IN ('accepted','reused') AND (inspection_state='pending' OR pending_parts)))),last_failure_code=NULLIF($3,''),retry_count=$7 WHERE id=$1 AND revision=$4 AND retry_count=$8`, work.Provider.ID, command.Delay.String(), command.Code, work.Provider.Revision, work.Provider.SourceGeneration, work.Run.MailboxGeneration, command.RetryCount, command.Facts.RetryCount)
		if err != nil {
			return err
		}
		if tag.RowsAffected() != 1 {
			return m.ErrConflict
		}
		_, err = tx.Exec(ctx, `UPDATE email_runs SET status=$2,stage=$3,failure_code=NULLIF($4,''),has_more=$5,finished_at=clock_timestamp(),attempt_token=NULL,attempt_deadline=NULL WHERE id=$1`, attempt.RunID, command.Status, command.Stage, command.Code, command.More)
		return err
	})
}
