package datasources

import (
	"context"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"slices"
	"time"
)

func (s *ChatDataSource) Dispatch(ctx context.Context) ([]m.ChatDispatch, error) {
	result := []m.ChatDispatch{}
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		var singleton bool
		if err := tx.QueryRow(ctx, "SELECT singleton FROM chat_admission WHERE singleton FOR UPDATE").Scan(&singleton); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT c.id,c.workflow_id,c.provider,c.base_url,c.internal_runtime FROM chat_turns c LEFT JOIN scheduler_waiting_requests q ON q.workflow_id=c.workflow_id WHERE c.status='queued' AND c.admitted_at IS NULL AND NOT c.execution_closed ORDER BY CASE WHEN q.feasible THEN 0 WHEN q.workflow_id IS NULL THEN 1 ELSE 2 END,q.sequence NULLS LAST,c.created_at,c.id LIMIT 20 FOR UPDATE OF c`)
		if err != nil {
			return err
		}
		type candidate struct {
			id, workflow, provider, endpoint string
			internal                         bool
		}
		var candidates []candidate
		for rows.Next() {
			var c candidate
			if err = rows.Scan(&c.id, &c.workflow, &c.provider, &c.endpoint, &c.internal); err != nil {
				rows.Close()
				return err
			}
			candidates = append(candidates, c)
		}
		rows.Close()
		if err = rows.Err(); err != nil {
			return err
		}
		for _, c := range candidates {
			providers := m.ChatSchedulerProviders(c.endpoint, c.internal)
			if s.scheduler == nil {
				return errors.New("chat resource scheduler is not configured")
			}
			admitted, e := s.scheduler.Reserve(ctx, tx, c.workflow, "chat", providers)
			if e != nil {
				return e
			}
			if !admitted {
				continue
			}
			if _, e = tx.Exec(ctx, "UPDATE chat_turns SET admitted_at=clock_timestamp(),first_start_at=clock_timestamp() WHERE id=$1", c.id); e != nil {
				return e
			}
		}
		rows, err = tx.Query(ctx, `SELECT id,account_id,workflow_id,task_queue,run_id,first_start_at,status='cancelled' FROM chat_turns WHERE admitted_at IS NOT NULL AND NOT execution_closed AND next_check_at<=clock_timestamp() AND (delivery_expires_at IS NULL OR delivery_expires_at<clock_timestamp()) ORDER BY next_check_at,created_at LIMIT 3 FOR UPDATE`)
		if err != nil {
			return err
		}
		for rows.Next() {
			var d m.ChatDispatch
			if err := rows.Scan(&d.TurnID, &d.AccountID, &d.WorkflowID, &d.TaskQueue, &d.RunID, &d.FirstStartAt, &d.CancelRequested); err != nil {
				rows.Close()
				return err
			}
			d.DeliveryToken = uuid.NewString()
			result = append(result, d)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		for _, d := range result {
			if _, err := tx.Exec(ctx, "UPDATE chat_turns SET delivery_token=$2,delivery_expires_at=clock_timestamp()+interval '30 seconds' WHERE id=$1", d.TurnID, d.DeliveryToken); err != nil {
				return err
			}
		}
		return nil
	})
	return result, err
}
func (s *ChatDataSource) Acknowledge(ctx context.Context, d m.ChatDispatch, run string) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, "UPDATE chat_turns SET run_id=$3,delivery_token=NULL,delivery_expires_at=NULL,next_check_at=clock_timestamp()+interval '2 seconds' WHERE id=$1 AND delivery_token=$2 AND (run_id='' OR run_id=$3)", d.TurnID, d.DeliveryToken, run)
		return err
	})
}
func (s *ChatDataSource) ReleaseDelivery(ctx context.Context, d m.ChatDispatch) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, "UPDATE chat_turns SET delivery_token=NULL,delivery_expires_at=NULL,next_check_at=clock_timestamp()+interval '2 seconds' WHERE id=$1 AND delivery_token=$2", d.TurnID, d.DeliveryToken)
		return err
	})
}
func (s *ChatDataSource) Closed(ctx context.Context, d m.ChatDispatch, command m.ChatClosureCommand) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		var conversation string
		if err := tx.QueryRow(ctx, "SELECT c.id FROM chat_conversations c JOIN chat_turns t ON t.conversation_id=c.id WHERE t.id=$1 FOR UPDATE OF c", d.TurnID).Scan(&conversation); errors.Is(err, pgx.ErrNoRows) {
			return nil
		} else if err != nil {
			return err
		}
		err := tx.QueryRow(ctx, `UPDATE chat_turns SET execution_closed=true,delivery_token=NULL,delivery_expires_at=NULL,status=CASE WHEN status=ANY($4::text[]) THEN $5 ELSE status END,stage=CASE WHEN status=ANY($4::text[]) THEN $5 ELSE stage END,failure_code=CASE WHEN status=ANY($4::text[]) THEN $3 ELSE failure_code END,updated_at=clock_timestamp(),finished_at=COALESCE(finished_at,clock_timestamp()) WHERE id=$1 AND delivery_token=$2 AND (execution_token IS NULL OR execution_drained_at IS NOT NULL OR execution_expires_at<clock_timestamp()) RETURNING conversation_id`, d.TurnID, d.DeliveryToken, command.FailureCode, command.ExpectedStates, command.Status).Scan(&conversation)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		return chatScrubDeletedTx(ctx, tx, conversation, command.Cleanup)
	})
}
func (s *ChatDataSource) executionTx(ctx context.Context, id, token string, fn func(pgx.Tx, m.ChatActor, string) error) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL statement_timeout='5s'"); err != nil {
			return err
		}
		var a m.ChatActor
		var conversation string
		if err := tx.QueryRow(ctx, "SELECT account_id,owner_id,credential_revision,conversation_id FROM chat_turns WHERE id=$1", id).Scan(&a.AccountID, &a.UserID, &a.CredentialRevision, &conversation); err != nil {
			return chatUnavailable(err, m.ErrNotFound)
		}
		if _, err := lockChatConversation(ctx, tx, a, conversation); err != nil {
			return err
		}
		var valid bool
		if err := tx.QueryRow(ctx, "SELECT status IN ('queued','running') AND execution_token=$2 AND execution_expires_at>clock_timestamp() AND NOT execution_closed FROM chat_turns WHERE id=$1 FOR UPDATE", id, token).Scan(&valid); err != nil {
			return err
		}
		if !valid {
			return m.ErrCancelled
		}
		return fn(tx, a, conversation)
	})
}
func (s *ChatDataSource) Acquire(ctx context.Context, id, token string, command m.ChatAcquisitionCommand) error {
	_, err := s.acquire(ctx, id, token, command)
	return err
}
func (s *ChatDataSource) AcquireStep(ctx context.Context, id, token string, command m.ChatAcquisitionCommand) (bool, error) {
	return s.acquire(ctx, id, token, command)
}
func (s *ChatDataSource) acquire(ctx context.Context, id, token string, command m.ChatAcquisitionCommand) (bool, error) {
	completed := false
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL statement_timeout='5s'"); err != nil {
			return err
		}
		var a m.ChatActor
		var conversation string
		if err := tx.QueryRow(ctx, "SELECT account_id,owner_id,credential_revision,conversation_id FROM chat_turns WHERE id=$1", id).Scan(&a.AccountID, &a.UserID, &a.CredentialRevision, &conversation); err != nil {
			return chatUnavailable(err, m.ErrNotFound)
		}
		if _, err := lockChatConversation(ctx, tx, a, conversation); err != nil {
			return err
		}
		var status string
		var current *string
		var expires *time.Time
		var closed, admitted bool
		if err := tx.QueryRow(ctx, "SELECT status,execution_token::text,execution_expires_at,execution_closed,admitted_at IS NOT NULL FROM chat_turns WHERE id=$1 FOR UPDATE", id).Scan(&status, &current, &expires, &closed, &admitted); err != nil {
			return err
		}
		if command.ReplayState != "" && status == command.ReplayState {
			completed = true
			return nil
		}
		if !admitted || closed || !slices.Contains(command.ExpectedStates, status) {
			return m.ErrCancelled
		}
		if current != nil && *current != token && expires != nil && time.Now().Before(*expires) {
			return m.ChatProcessingError{Code: "execution_busy", Retryable: true}
		}
		_, err := tx.Exec(ctx, "UPDATE chat_turns SET execution_token=$2,execution_expires_at=clock_timestamp()+make_interval(secs=>$3),execution_drained_at=NULL,status=$4,stage=$5,updated_at=clock_timestamp() WHERE id=$1", id, token, command.Lease.Seconds(), command.Status, command.Stage)
		return err
	})
	return completed, err
}
func (s *ChatDataSource) Renew(ctx context.Context, id, token string, query m.ChatContextQuery) error {
	return s.executionTx(ctx, id, token, func(tx pgx.Tx, a m.ChatActor, conversation string) error {
		if err := s.evidenceExists(ctx, tx, conversation, id, query); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, "UPDATE chat_turns SET execution_expires_at=clock_timestamp()+interval '180 seconds' WHERE id=$1 AND execution_token=$2", id, token)
		return err
	})
}
func (s *ChatDataSource) Release(ctx context.Context, id, token string) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, "UPDATE chat_turns SET execution_token=NULL,execution_expires_at=NULL,execution_drained_at=clock_timestamp() WHERE id=$1 AND execution_token=$2", id, token)
		return err
	})
}
func (s *ChatDataSource) SetStage(ctx context.Context, id, token, stage string) error {
	return s.executionTx(ctx, id, token, func(tx pgx.Tx, _ m.ChatActor, _ string) error {
		_, err := tx.Exec(ctx, "UPDATE chat_turns SET stage=$3,updated_at=clock_timestamp() WHERE id=$1 AND execution_token=$2 AND stage<>$3", id, token, stage)
		return err
	})
}
func (s *ChatDataSource) Fail(ctx context.Context, id string, command m.ChatClosureCommand) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, "UPDATE chat_turns SET status=$4,stage=$5,failure_code=$2,execution_closed=CASE WHEN admitted_at IS NULL THEN true ELSE execution_closed END,updated_at=clock_timestamp(),finished_at=clock_timestamp() WHERE id=$1 AND status=ANY($3::text[])", id, command.FailureCode, command.ExpectedStates, command.Status, command.Stage)
		return err
	})
}
func (s *ChatDataSource) evidenceExists(ctx context.Context, tx pgx.Tx, conversation, id string, query m.ChatContextQuery) error {
	var present, missing bool
	err := tx.QueryRow(ctx, `WITH history AS (SELECT m.turn_id,m.role FROM chat_messages m JOIN chat_turns t ON t.id=m.turn_id WHERE m.conversation_id=$1 AND m.sequence<=(SELECT sequence FROM chat_messages WHERE turn_id=$2 AND role='user') AND (m.role='user' OR t.status=$4) ORDER BY sequence DESC LIMIT $3), evidence AS (SELECT s.document_id,t.account_id FROM chat_sources s JOIN chat_turns t ON t.id=s.turn_id WHERE t.id=$2 OR t.id IN(SELECT turn_id FROM history WHERE role='assistant')) SELECT EXISTS(SELECT 1 FROM evidence),EXISTS(SELECT 1 FROM evidence e LEFT JOIN documents d ON d.id=e.document_id AND d.account_id=e.account_id WHERE d.id IS NULL)`, conversation, id, query.MessageLimit, query.AssistantStatus).Scan(&present, &missing)
	if err != nil {
		return err
	}
	if missing {
		return m.ChatProcessingError{Code: "document_unavailable"}
	}
	return nil
}
func (s *ChatDataSource) Complete(ctx context.Context, id, token, content string, query m.ChatContextQuery) error {
	if err := (m.ChatAction{Kind: "answer", Content: content}).Validate(); err != nil {
		return err
	}
	return s.executionTx(ctx, id, token, func(tx pgx.Tx, a m.ChatActor, conversation string) error {
		if err := s.evidenceExists(ctx, tx, conversation, id, query); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, "UPDATE chat_messages SET content=$2,updated_at=clock_timestamp() WHERE turn_id=$1 AND role='assistant'", id, content); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, "UPDATE chat_turns SET status='completed',stage='completed',updated_at=clock_timestamp(),finished_at=clock_timestamp() WHERE id=$1", id)
		return err
	})
}
