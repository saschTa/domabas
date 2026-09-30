package datasources

import (
	"context"
	"errors"
	"slices"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (s *EmailDataSource) NextDelivery(ctx context.Context, keyIDs ...string) (string, error) {
	var runID string
	err := s.database.QueryRow(ctx, `SELECT o.run_id FROM email_outbox o JOIN email_runs r ON r.id=o.run_id LEFT JOIN email_providers p ON p.id=r.provider_id LEFT JOIN scheduler_requests q ON q.workflow_id='domabas-email-'||r.id::text AND q.state='waiting' WHERE o.acknowledged_at IS NULL AND o.available_at<=clock_timestamp() AND (o.lease_expires_at IS NULL OR o.lease_expires_at<=clock_timestamp()) AND r.status IN ('queued','running') AND ($1::text[] IS NULL OR p.credential_key_id=ANY($1)) ORDER BY EXISTS(SELECT 1 FROM email_executions e WHERE e.run_id=o.run_id AND e.closed_at IS NULL) DESC,q.sequence NULLS LAST,o.available_at,o.run_id LIMIT 1`, keyIDs).Scan(&runID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return runID, nil
}
func (s *EmailDataSource) ClaimDelivery(ctx context.Context, queue string, keyIDs ...string) (*m.EmailExecution, error) {
	runID, err := s.NextDelivery(ctx, keyIDs...)
	if err != nil || runID == "" {
		return nil, err
	}
	return s.ClaimDeliveryFor(ctx, queue, runID, keyIDs...)
}
func (s *EmailDataSource) ClaimDeliveryFor(ctx context.Context, queue, runID string, keyIDs ...string) (*m.EmailExecution, error) {
	identity, err := s.runIdentity(ctx, runID)
	if err != nil {
		return nil, err
	}
	var result *m.EmailExecution
	err = s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		provider, _, err := s.currentRun(ctx, tx, identity)
		if err != nil {
			return err
		}
		if keyIDs != nil && !slices.Contains(keyIDs, provider.KeyID) {
			return nil
		}
		var locked bool
		if err = tx.QueryRow(ctx, `SELECT id FROM email_admission WHERE id=true FOR UPDATE`).Scan(&locked); err != nil {
			return err
		}
		var eligible bool
		if err = tx.QueryRow(ctx, `SELECT acknowledged_at IS NULL AND available_at<=clock_timestamp() AND (lease_expires_at IS NULL OR lease_expires_at<=clock_timestamp()) FROM email_outbox WHERE run_id=$1 FOR UPDATE`, runID).Scan(&eligible); err != nil || !eligible {
			return err
		}
		workflow := "domabas-email-" + runID
		if s.scheduler == nil {
			return errors.New("email resource scheduler is not configured")
		}
		admitted, err := s.scheduler.Reserve(ctx, tx, workflow, "email", nil)
		if err != nil || !admitted {
			return err
		}
		if _, err = tx.Exec(ctx, `INSERT INTO email_executions(run_id,workflow_id,task_queue,first_attempt_at,start_window_end) VALUES($1,$2,$3,statement_timestamp(),statement_timestamp()+$4::interval) ON CONFLICT(run_id) DO NOTHING`, runID, workflow, queue, emailExecutionStartWindow.String()); err != nil {
			return err
		}
		lease := m.EmailExecution{RunID: runID, LeaseToken: uuid.NewString()}
		err = tx.QueryRow(ctx, `UPDATE email_executions SET latest_permit_end=LEAST(clock_timestamp()+$2::interval,start_window_end),next_check_at=clock_timestamp()+$3::interval WHERE run_id=$1 AND workflow_run_id IS NULL AND closed_at IS NULL AND terminal_fenced_at IS NULL AND start_window_end>clock_timestamp() RETURNING workflow_id,task_queue,first_attempt_at,start_window_end,latest_permit_end`, runID, emailExecutionStartPermit.String(), emailExecutionCheckInterval.String()).Scan(&lease.WorkflowID, &lease.TaskQueue, &lease.FirstAttemptAt, &lease.StartWindowEnd, &lease.LatestPermitEnd)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, `UPDATE email_outbox SET lease_token=$2,lease_expires_at=$3,available_at=clock_timestamp()+$4::interval WHERE run_id=$1`, runID, lease.LeaseToken, lease.LatestPermitEnd, emailExecutionCheckInterval.String()); err != nil {
			return err
		}
		result = &lease
		return nil
	})
	return result, err
}
func retireDelivery(ctx context.Context, tx pgx.Tx, identity m.EmailRun, command m.EmailRetirementCommand) error {
	if _, err := tx.Exec(ctx, `SELECT id FROM email_providers WHERE id=$1 FOR UPDATE`, identity.ProviderID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE email_runs SET status=$2,stage=$3,failure_code=$4,finished_at=clock_timestamp(),attempt_token=NULL,attempt_deadline=NULL WHERE id=$1 AND status IN ('queued','running')`, identity.ID, command.Status, command.Stage, command.Code); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE email_executions SET terminal_fenced_at=COALESCE(terminal_fenced_at,clock_timestamp()),next_check_at=clock_timestamp() WHERE run_id=$1 AND closed_at IS NULL`, identity.ID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE email_outbox SET acknowledged_at=COALESCE(acknowledged_at,clock_timestamp()),lease_token=NULL,lease_expires_at=NULL WHERE run_id=$1`, identity.ID); err != nil {
		return err
	}
	return nil
}
func (s *EmailDataSource) Retire(ctx context.Context, command m.EmailRetirementCommand) error {
	identity, err := s.runIdentity(ctx, command.RunID)
	if err != nil {
		return translate(err)
	}
	return s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error { return retireDelivery(ctx, tx, identity, command) })
}
func (s *EmailDataSource) AcknowledgeDelivery(ctx context.Context, execution m.EmailExecution, run string) error {
	return s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		var id string
		if err := tx.QueryRow(ctx, `SELECT id FROM email_runs WHERE id=$1 FOR UPDATE`, execution.RunID).Scan(&id); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE email_executions SET workflow_run_id=$4,next_check_at=clock_timestamp()+$5::interval WHERE run_id=$1 AND workflow_id=$2 AND task_queue=$3 AND (workflow_run_id IS NULL OR workflow_run_id=$4) AND closed_at IS NULL`, execution.RunID, execution.WorkflowID, execution.TaskQueue, run, emailExecutionCheckInterval.String())
		if err != nil {
			return err
		}
		if tag.RowsAffected() != 1 {
			return m.ErrConflict
		}
		if _, err = tx.Exec(ctx, `UPDATE email_runs SET workflow_run_id=$2 WHERE id=$1 AND (workflow_run_id IS NULL OR workflow_run_id=$2)`, execution.RunID, run); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE email_outbox SET acknowledged_at=clock_timestamp(),lease_token=NULL,lease_expires_at=NULL WHERE run_id=$1`, execution.RunID)
		return err
	})
}
func (s *EmailDataSource) PendingExecutions(ctx context.Context) ([]m.EmailExecution, error) {
	result := []m.EmailExecution{}
	err := s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `WITH selected AS(SELECT run_id FROM email_executions WHERE closed_at IS NULL AND next_check_at<=clock_timestamp() ORDER BY next_check_at,run_id LIMIT 20 FOR UPDATE SKIP LOCKED) UPDATE email_executions e SET next_check_at=clock_timestamp()+$1::interval FROM selected s WHERE e.run_id=s.run_id RETURNING e.run_id::text,e.workflow_id,COALESCE(e.workflow_run_id,''),e.task_queue,e.first_attempt_at,e.start_window_end,COALESCE(e.latest_permit_end,e.first_attempt_at),e.terminal_fenced_at IS NOT NULL`, emailExecutionCheckLease.String())
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var execution m.EmailExecution
			if err = rows.Scan(&execution.RunID, &execution.WorkflowID, &execution.WorkflowRunID, &execution.TaskQueue, &execution.FirstAttemptAt, &execution.StartWindowEnd, &execution.LatestPermitEnd, &execution.Terminal); err != nil {
				return err
			}
			result = append(result, execution)
		}
		return rows.Err()
	})
	return result, err
}
func (s *EmailDataSource) ExecutionFacts(ctx context.Context, e m.EmailExecution) (m.EmailExecutionFacts, error) {
	var facts m.EmailExecutionFacts
	err := s.database.QueryRow(ctx, `SELECT r.status,e.workflow_id,e.task_queue,COALESCE(e.workflow_run_id,''),e.latest_permit_end,e.closed_at,clock_timestamp() FROM email_executions e JOIN email_runs r ON r.id=e.run_id WHERE e.run_id=$1`, e.RunID).Scan(&facts.Status, &facts.WorkflowID, &facts.TaskQueue, &facts.WorkflowRunID, &facts.PermitEnd, &facts.ClosedAt, &facts.ObservedAt)
	return facts, translate(err)
}
func sameEmailTimestamp(left, right *time.Time) bool {
	return left == nil && right == nil || left != nil && right != nil && left.Equal(*right)
}
func (s *EmailDataSource) ResolveExecution(ctx context.Context, command m.EmailExecutionClosureCommand) error {
	execution := command.Execution
	return s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		var current m.EmailExecutionFacts
		if err := tx.QueryRow(ctx, `SELECT status FROM email_runs WHERE id=$1 FOR UPDATE`, execution.RunID).Scan(&current.Status); err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, `SELECT workflow_id,task_queue,COALESCE(workflow_run_id,''),latest_permit_end,closed_at,clock_timestamp() FROM email_executions WHERE run_id=$1 FOR UPDATE`, execution.RunID).Scan(&current.WorkflowID, &current.TaskQueue, &current.WorkflowRunID, &current.PermitEnd, &current.ClosedAt, &current.ObservedAt); err != nil {
			return err
		}
		expected := command.Expected
		if current.Status != expected.Status || current.WorkflowID != expected.WorkflowID || current.TaskQueue != expected.TaskQueue || current.WorkflowRunID != expected.WorkflowRunID || !sameEmailTimestamp(current.PermitEnd, expected.PermitEnd) || !sameEmailTimestamp(current.ClosedAt, expected.ClosedAt) {
			return m.ErrConflict
		}
		if command.EarliestClosure != nil && current.ObservedAt.Before(*command.EarliestClosure) {
			return m.ErrConflict
		}
		if command.FailRun {
			if _, err := tx.Exec(ctx, `UPDATE email_runs SET status='failed',failure_code=$2,finished_at=clock_timestamp(),attempt_token=NULL,attempt_deadline=NULL WHERE id=$1`, execution.RunID, command.FailureCode); err != nil {
				return err
			}
		}
		if _, err := tx.Exec(ctx, `UPDATE email_executions SET closed_at=clock_timestamp(),terminal_fenced_at=clock_timestamp(),workflow_run_id=COALESCE(workflow_run_id,NULLIF($2,'')) WHERE run_id=$1`, execution.RunID, command.ObservedRun); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE email_outbox SET acknowledged_at=COALESCE(acknowledged_at,clock_timestamp()),lease_token=NULL,lease_expires_at=NULL WHERE run_id=$1`, execution.RunID)
		return err
	})
}
