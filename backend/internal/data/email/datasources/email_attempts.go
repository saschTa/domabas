package datasources

import (
	"context"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/email/models"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/jackc/pgx/v5"
)

func (s *EmailDataSource) runIdentity(ctx context.Context, id string) (m.EmailRun, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	return scanRun(s.database.QueryRow(ctx, `SELECT `+runColumns+` FROM email_runs WHERE id=$1`, id))
}
func (s *EmailDataSource) currentRun(ctx context.Context, tx pgx.Tx, identity m.EmailRun) (r.EmailProviderRecord, m.EmailRun, error) {
	a := m.EmailActor{AccountID: identity.AccountID, UserID: identity.OwnerID}
	provider, err := lockProvider(ctx, tx, a, identity.ProviderID)
	if err != nil {
		return provider, m.EmailRun{}, err
	}
	if !provider.Provider.Enabled || provider.Provider.ConsentRevision <= 0 || provider.Provider.Revision != identity.ProviderRevision || provider.Provider.SourceGeneration != identity.SourceGeneration {
		return provider, m.EmailRun{}, m.ErrStaleAttempt
	}
	run, err := scanRun(tx.QueryRow(ctx, `SELECT `+runColumns+` FROM email_runs WHERE id=$1 AND status IN ('queued','running') FOR UPDATE`, identity.ID))
	return provider, run, err
}
func (s *EmailDataSource) ClaimAttempt(ctx context.Context, attempt m.EmailAttempt, admission m.EmailAttemptAdmission) (r.EmailWorkRecord, error) {
	result := r.EmailWorkRecord{}
	identity, err := s.runIdentity(ctx, attempt.RunID)
	if err != nil {
		return result, translate(err)
	}
	err = s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		provider, run, err := s.currentRun(ctx, tx, identity)
		if err == nil && provider.Provider.ConsentRevision != attempt.ConsentRevision {
			return m.ErrStaleAttempt
		}
		if err != nil {
			return err
		}
		var workflow, queue string
		var workflowRun *string
		var first, window time.Time
		var permit, closed *time.Time
		if err = tx.QueryRow(ctx, `SELECT workflow_id,task_queue,workflow_run_id,first_attempt_at,start_window_end,latest_permit_end,closed_at FROM email_executions WHERE run_id=$1 FOR UPDATE`, attempt.RunID).Scan(&workflow, &queue, &workflowRun, &first, &window, &permit, &closed); err != nil {
			return m.ErrStaleAttempt
		}
		if workflow != attempt.WorkflowID || queue != attempt.TaskQueue || closed != nil {
			return m.ErrStaleAttempt
		}
		if workflowRun != nil && *workflowRun != attempt.WorkflowRunID {
			return m.ErrStaleAttempt
		}
		if workflowRun == nil {
			if permit == nil || attempt.ExecutionStartedAt.Before(first.Add(-emailExecutionClockAllowance)) || attempt.ExecutionStartedAt.After(permit.Add(emailExecutionClockAllowance)) || attempt.ExecutionStartedAt.After(window.Add(emailExecutionClockAllowance)) {
				return m.ErrStaleAttempt
			}
			if _, err = tx.Exec(ctx, `UPDATE email_executions SET workflow_run_id=$2 WHERE run_id=$1 AND workflow_run_id IS NULL`, attempt.RunID, attempt.WorkflowRunID); err != nil {
				return err
			}
		}
		var page, number int
		var activity, token *string
		if err = tx.QueryRow(ctx, `SELECT page_index,activity_attempt,activity_id,attempt_token::text FROM email_runs WHERE id=$1`, attempt.RunID).Scan(&page, &number, &activity, &token); err != nil {
			return err
		}
		same := attempt.PageIndex == page && activity != nil && *activity == attempt.ActivityID
		if !(attempt.PageIndex == page+1 || same && attempt.Number > number || same && attempt.Number == number && token != nil && *token == attempt.Token) {
			return m.ErrStaleAttempt
		}
		var deadline time.Time
		err = tx.QueryRow(ctx, `UPDATE email_runs SET status=$8,stage=$9,started_at=COALESCE(started_at,clock_timestamp()),page_index=$2,activity_id=$3,activity_attempt=$4,attempt_token=$5,attempt_deadline=LEAST($6,clock_timestamp()+$10::interval),workflow_run_id=$7 WHERE id=$1 AND $6>clock_timestamp() RETURNING attempt_deadline`, attempt.RunID, attempt.PageIndex, attempt.ActivityID, attempt.Number, attempt.Token, attempt.Deadline, attempt.WorkflowRunID, admission.Status, admission.Stage, emailActivityMaximumLease.String()).Scan(&deadline)
		if err != nil {
			return m.ErrStaleAttempt
		}
		attempt.Deadline = deadline
		run.Status = admission.Status
		result = r.EmailWorkRecord{Attempt: r.EmailAttempt(attempt), Run: r.EmailRun(run), Provider: provider}
		return nil
	})
	return result, err
}
func (s *EmailDataSource) attemptTx(ctx context.Context, attempt m.EmailAttempt, fn func(context.Context, pgx.Tx, m.EmailWork) error) error {
	identity, err := s.runIdentity(ctx, attempt.RunID)
	if err != nil {
		return translate(err)
	}
	return s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		provider, run, err := s.currentRun(ctx, tx, identity)
		if err == nil && provider.Provider.ConsentRevision != attempt.ConsentRevision {
			return m.ErrStaleAttempt
		}
		if err != nil {
			return err
		}
		var valid bool
		err = tx.QueryRow(ctx, `SELECT status='running' AND page_index=$2 AND activity_id=$3 AND activity_attempt=$4 AND attempt_token=$5 AND attempt_deadline>clock_timestamp() AND workflow_run_id=$6 FROM email_runs WHERE id=$1`, attempt.RunID, attempt.PageIndex, attempt.ActivityID, attempt.Number, attempt.Token, attempt.WorkflowRunID).Scan(&valid)
		if err != nil || !valid {
			return m.ErrStaleAttempt
		}
		return fn(ctx, tx, m.EmailWork{Attempt: attempt, Provider: emailProviderRecordMapper(provider.Provider), Run: run})
	})
}
func (s *EmailDataSource) SetStage(ctx context.Context, attempt m.EmailAttempt, stage string) error {
	return s.attemptTx(ctx, attempt, func(ctx context.Context, tx pgx.Tx, work m.EmailWork) error {
		_, err := tx.Exec(ctx, `UPDATE email_runs SET stage=$2 WHERE id=$1`, attempt.RunID, stage)
		return err
	})
}
