package datasources

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	schedulermodels "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

const aiSummaryColumns = `id,status,stage,attempt,configuration_revision,failure_code,updated_at,started_at,finished_at,COALESCE(invoice_decision,''),COALESCE(invoice_decision_reason,''),invoice_classification_pass,invoice_input_characters,invoice_source_characters`

func scanAI(row pgx.Row) (r.DocumentAIProcessingRecord, error) {
	var result r.DocumentAIProcessingRecord
	err := row.Scan(&result.JobID, &result.Status, &result.Stage, &result.Attempt, &result.ConfigurationRevision, &result.FailureCode, &result.UpdatedAt, &result.StartedAt, &result.FinishedAt, &result.InvoiceDecision, &result.InvoiceDecisionReason, &result.InvoiceClassificationPass, &result.InvoiceInputCharacters, &result.InvoiceSourceCharacters)
	return result, err
}

func lockAI(ctx context.Context, tx pgx.Tx, j m.DocumentJob) (string, error) {
	if err := lockDocument(ctx, tx, j.AccountID, j.DocumentID); err != nil {
		return "", staleError(err)
	}
	var stage string
	err := tx.QueryRow(ctx, `SELECT a.stage FROM document_ai_jobs a JOIN document_processing p ON p.account_id=a.account_id AND p.document_id=a.document_id AND p.generation=a.generation AND p.ocr_revision=a.ocr_revision JOIN documents d ON d.account_id=a.account_id AND d.id=a.document_id AND d.ocr_revision=a.ocr_revision WHERE a.account_id=$1 AND a.document_id=$2 AND a.generation=$3 AND a.attempt=$4 AND p.state='ready' AND a.status IN ('queued','running') AND a.attempt=(SELECT max(attempt) FROM document_ai_jobs WHERE account_id=$1 AND document_id=$2) FOR UPDATE OF a`, j.AccountID, j.DocumentID, j.Generation, j.AIAttempt).Scan(&stage)
	return stage, staleError(err)
}

func readAIEnqueueFacts(ctx context.Context, tx pgx.Tx, account, id string) (m.DocumentAIEnqueueFacts, error) {
	var facts m.DocumentAIEnqueueFacts
	err := tx.QueryRow(ctx, "SELECT p.state,p.generation,p.ocr_revision,p.invoice_xml IS NOT NULL OR p.invoice_failure_code IS NOT NULL,d.ocr_manual_text IS NOT NULL,COALESCE(a.attempt,0),COALESCE(a.status,'') FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id AND d.ocr_revision=p.ocr_revision LEFT JOIN LATERAL(SELECT attempt,status FROM document_ai_jobs WHERE account_id=p.account_id AND document_id=p.document_id ORDER BY attempt DESC LIMIT 1)a ON true WHERE p.account_id=$1 AND p.document_id=$2", account, id).Scan(&facts.State, &facts.Generation, &facts.OCRRevision, &facts.HasInvoiceEvidence, &facts.ManualText, &facts.LatestAttempt, &facts.LatestStatus)
	return facts, err
}
func enqueueAI(ctx context.Context, tx pgx.Tx, account, id, requestID, reason string, command m.DocumentAIEnqueueCommand, user string) (r.DocumentAIProcessingRecord, error) {
	c := command.Configuration
	snapshot, err := json.Marshal(c)
	if err != nil {
		return r.DocumentAIProcessingRecord{}, err
	}
	if _, err = tx.Exec(ctx, "UPDATE document_ai_jobs SET status='superseded',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND status IN ('queued','running')", account, id); err != nil {
		return r.DocumentAIProcessingRecord{}, err
	}
	return scanAI(tx.QueryRow(ctx, `INSERT INTO document_ai_jobs(id,account_id,document_id,generation,attempt,ocr_revision,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,initiated_by_user_id,finished_at)
 VALUES(COALESCE(NULLIF($3,'')::uuid,gen_random_uuid()),$1,$2,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,NULLIF($14,'')::uuid,CASE WHEN $15 THEN clock_timestamp() END) RETURNING `+aiSummaryColumns, account, id, requestID, command.Expected.Generation, command.Expected.LatestAttempt+1, command.Expected.OCRRevision, reason, c.Revision, c.Fingerprint, snapshot, command.Status, command.Stage, command.TextSource, user, command.Finished))
}
func readAIRetryFacts(ctx context.Context, tx pgx.Tx, a m.DocumentActor, id, request string) (m.DocumentAIRetryFacts, error) {
	var facts m.DocumentAIRetryFacts
	var err error
	facts.Configuration, err = readConfiguration(ctx, tx)
	if err != nil {
		return facts, err
	}
	facts.Enqueue, err = readAIEnqueueFacts(ctx, tx, a.AccountID, id)
	if err != nil {
		return facts, err
	}
	err = tx.QueryRow(ctx, "SELECT COALESCE(initiated_by_user_id::text,''),document_id,account_id,configuration_revision FROM document_ai_jobs WHERE id=$1", request).Scan(&facts.RequestOwner, &facts.RequestDocument, &facts.RequestAccount, &facts.RequestRevision)
	if err == nil {
		facts.RequestExists = true
		record, err := scanAI(tx.QueryRow(ctx, "SELECT "+aiSummaryColumns+" FROM document_ai_jobs WHERE id=$1", request))
		facts.Existing = m.DocumentAIProcessing(record)
		return facts, err
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return facts, err
	}
	err = tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM document_processing_jobs WHERE id=$1)", request).Scan(&facts.RequestCollision)
	return facts, err
}
func (s *DocumentDataSource) AIRetryFacts(ctx context.Context, a m.DocumentActor, id, request string) (m.DocumentAIRetryFacts, error) {
	var facts m.DocumentAIRetryFacts
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var err error
		facts, err = readAIRetryFacts(ctx, tx, a, id, request)
		return err
	})
	return facts, err
}
func (s *DocumentDataSource) AIRetryRecord(ctx context.Context, a m.DocumentActor, id string, command m.DocumentAIRetryCommand) (r.DocumentAIProcessingRecord, error) {
	var out r.DocumentAIProcessingRecord
	err := s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		if _, err := prepareGeneration(ctx, tx); err != nil {
			return err
		}
		if err := lockDocument(ctx, tx, a.AccountID, id); err != nil {
			return err
		}
		facts, err := readAIRetryFacts(ctx, tx, a, id, command.RequestID)
		if err != nil {
			return err
		}
		if !reflect.DeepEqual(facts, command.Expected) {
			return m.ErrConflict
		}
		out, err = enqueueAI(ctx, tx, a.AccountID, id, command.RequestID, "retry", command.Enqueue, a.UserID)
		return err
	})
	return out, err
}

func (s *DocumentDataSource) AICompletionFacts(ctx context.Context, j m.DocumentJob) (m.DocumentAICompletionFacts, error) {
	var facts m.DocumentAICompletionFacts
	err := s.database.QueryRow(ctx, `SELECT a.status,a.stage,EXISTS(SELECT 1 FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id WHERE p.account_id=a.account_id AND p.document_id=a.document_id AND p.generation=a.generation AND p.ocr_revision=a.ocr_revision AND d.ocr_revision=a.ocr_revision AND p.state='ready' AND a.attempt=(SELECT max(attempt) FROM document_ai_jobs WHERE account_id=a.account_id AND document_id=a.document_id)) FROM document_ai_jobs a WHERE a.account_id=$1 AND a.document_id=$2 AND a.generation=$3 AND a.attempt=$4`, j.AccountID, j.DocumentID, j.Generation, j.AIAttempt).Scan(&facts.Status, &facts.Stage, &facts.Current)
	return facts, staleError(err)
}
func (s *DocumentDataSource) AIComplete(ctx context.Context, j m.DocumentJob, expected m.DocumentAICompletionFacts) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		stage, err := lockAI(ctx, tx, j)
		if err != nil {
			var succeeded bool
			if e := tx.QueryRow(ctx, `SELECT status='succeeded' FROM document_ai_jobs WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND attempt=$4`, j.AccountID, j.DocumentID, j.Generation, j.AIAttempt).Scan(&succeeded); e == nil && succeeded {
				return nil
			}
			return err
		}
		if stage != expected.Stage {
			return m.ErrStaleJob
		}
		_, err = tx.Exec(ctx, `UPDATE document_ai_jobs SET status='succeeded',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND attempt=$4`, j.AccountID, j.DocumentID, j.Generation, j.AIAttempt)
		return err
	})
}

func (s *DocumentDataSource) AIFail(ctx context.Context, j m.DocumentJob, code string) error {
	if !m.ValidFailureCode(code) {
		return m.DocumentValidationError{Message: "invalid AI failure code"}
	}
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if _, err := lockAI(ctx, tx, j); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE document_ai_jobs SET status='failed',failure_code=$5,finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND attempt=$4`, j.AccountID, j.DocumentID, j.Generation, j.AIAttempt, code)
		return err
	})
}

func aiWorkflowID(j m.DocumentJob) string {
	return fmt.Sprintf("document-ai-v1/%s/%s/%d/%d", j.AccountID, j.DocumentID, j.Generation, j.AIAttempt)
}

func (s *DocumentDataSource) AIClaim(ctx context.Context, limit int, lease time.Duration, policy m.DocumentDeliveryPolicy, queues ...string) ([]m.DocumentOutboxLease, error) {
	out := []m.DocumentOutboxLease{}
	queue := "domabas-documents-ai"
	if len(queues) > 0 && queues[0] != "" {
		queue = queues[0]
	}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL jit=off"); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended(current_database()||':'||current_schema()||':document-ai-admission',0))`); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT a.account_id,a.document_id,a.generation,a.attempt,a.scheduler_provider,a.scheduler_base_url
 FROM document_ai_jobs a JOIN document_processing p ON p.account_id=a.account_id AND p.document_id=a.document_id AND p.generation=a.generation AND p.ocr_revision=a.ocr_revision
 LEFT JOIN scheduler_waiting_requests q ON q.workflow_id='document-ai-v1/'||a.account_id::text||'/'||a.document_id::text||'/'||a.generation::text||'/'||a.attempt::text
 WHERE a.status='queued' AND a.admitted_at IS NULL AND p.state='ready'
 ORDER BY CASE WHEN q.feasible THEN 0 WHEN q.workflow_id IS NULL THEN 1 ELSE 2 END,q.sequence NULLS LAST,a.created_at,a.id LIMIT 20 FOR UPDATE OF a SKIP LOCKED`)
		if err != nil {
			return err
		}
		type candidate struct {
			job                m.DocumentJob
			provider, endpoint string
		}
		var candidates []candidate
		for rows.Next() {
			var c candidate
			if err = rows.Scan(&c.job.AccountID, &c.job.DocumentID, &c.job.Generation, &c.job.AIAttempt, &c.provider, &c.endpoint); err != nil {
				rows.Close()
				return err
			}
			candidates = append(candidates, c)
		}
		rows.Close()
		if err = rows.Err(); err != nil {
			return err
		}
		requests := make([]schedulermodels.SchedulerAdmissionCandidate, 0, len(candidates))
		for _, c := range candidates {
			var providers []string
			if c.provider == "ollama" {
				providers = append(providers, "ollama")
			} else if c.provider == "openai" {
				providers = append(providers, c.endpoint)
			}
			requests = append(requests, schedulermodels.SchedulerAdmissionCandidate{WorkflowID: aiWorkflowID(c.job), Providers: providers})
		}
		if s.scheduler == nil {
			return errors.New("document resource scheduler is not configured")
		}
		admitted, err := s.scheduler.ReserveFirst(ctx, tx, "document_ai", requests)
		if err != nil {
			return err
		}
		for _, c := range candidates {
			if aiWorkflowID(c.job) != admitted {
				continue
			}
			if _, e := tx.Exec(ctx, `UPDATE document_ai_jobs SET admitted_at=clock_timestamp(),delivery_deadline=clock_timestamp()+$7::interval,workflow_id=$5,task_queue=$6 WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND attempt=$4`, c.job.AccountID, c.job.DocumentID, c.job.Generation, c.job.AIAttempt, aiWorkflowID(c.job), queue, policy.DeliveryWindow.String()); e != nil {
				return e
			}
			break
		}
		var l m.DocumentOutboxLease
		l.UnlimitedInference = policy.ExecutionTimeout == 0
		err = tx.QueryRow(ctx, `WITH candidate AS(SELECT id FROM document_ai_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL AND run_id='' AND status IN ('queued','running') AND delivery_deadline>clock_timestamp() AND (start_retry_until IS NULL OR start_retry_until>clock_timestamp()) AND next_check_at<=clock_timestamp() AND (lease_expires_at IS NULL OR lease_expires_at<=clock_timestamp()) ORDER BY admitted_at LIMIT 1 FOR UPDATE SKIP LOCKED) UPDATE document_ai_jobs a SET first_permit_at=COALESCE(first_permit_at,clock_timestamp()),start_retry_until=COALESCE(start_retry_until,LEAST(delivery_deadline,clock_timestamp()+$1::interval)),latest_permit_end=LEAST(clock_timestamp()+$2::interval,delivery_deadline,COALESCE(start_retry_until,clock_timestamp()+$1::interval)),lease_token=gen_random_uuid(),lease_expires_at=clock_timestamp()+$3::interval,next_check_at=clock_timestamp()+$3::interval FROM candidate c WHERE a.id=c.id RETURNING a.id,a.lease_token,a.account_id,a.document_id,a.generation,a.attempt,a.delivery_deadline,a.workflow_id,a.task_queue,a.run_id,a.latest_permit_end,a.configuration_revision`, policy.StartRetryWindow.String(), policy.StartPermit.String(), policy.ClaimLease.String()).Scan(&l.ID, &l.LeaseToken, &l.Job.AccountID, &l.Job.DocumentID, &l.Job.Generation, &l.Job.AIAttempt, &l.DeliveryDeadline, &l.WorkflowID, &l.TaskQueue, &l.RunID, &l.PermitEnd, &l.ConfigurationRevision)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		out = append(out, l)
		return nil
	})
	return out, err
}

func (s *DocumentDataSource) AIAcknowledge(ctx context.Context, l m.DocumentOutboxLease, workflow, run string) error {
	if workflow != aiWorkflowID(l.Job) || run == "" {
		return m.ErrStaleJob
	}
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE document_ai_jobs SET run_id=$3,lease_token=NULL,lease_expires_at=NULL,next_check_at=clock_timestamp() WHERE id=$1 AND lease_token=$2 AND closed_at IS NULL AND (run_id='' OR run_id=$3)`, l.ID, l.LeaseToken, run)
		if err == nil && tag.RowsAffected() != 1 {
			return m.ErrStaleJob
		}
		return err
	})
}

func (s *DocumentDataSource) AIRelease(ctx context.Context, l m.DocumentOutboxLease, next time.Time) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE document_ai_jobs SET lease_token=NULL,lease_expires_at=NULL,next_check_at=$3 WHERE id=$1 AND lease_token=$2 AND closed_at IS NULL`, l.ID, l.LeaseToken, next)
		if err == nil && tag.RowsAffected() != 1 {
			return m.ErrStaleJob
		}
		return err
	})
}

func (s *DocumentDataSource) AIPending(ctx context.Context, limit int) ([]m.DocumentPendingJob, error) {
	out := []m.DocumentPendingJob{}
	if limit < 1 || limit > 100 {
		limit = 20
	}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `WITH candidate AS(SELECT id FROM document_ai_jobs WHERE status='queued' AND delivery_deadline<=clock_timestamp() AND started_at IS NULL ORDER BY delivery_deadline,id LIMIT 100 FOR UPDATE SKIP LOCKED) UPDATE document_ai_jobs a SET status='failed',failure_code='delivery_timeout',finished_at=clock_timestamp(),updated_at=clock_timestamp() FROM candidate c WHERE a.id=c.id`); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `WITH candidate AS(SELECT id FROM document_ai_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL AND next_check_at<=clock_timestamp() AND (lease_expires_at IS NULL OR lease_expires_at<=clock_timestamp()) ORDER BY next_check_at,admitted_at LIMIT $1 FOR UPDATE SKIP LOCKED) UPDATE document_ai_jobs a SET lease_token=gen_random_uuid(),lease_expires_at=clock_timestamp()+interval '30 seconds',next_check_at=clock_timestamp()+interval '15 seconds' FROM candidate c WHERE a.id=c.id RETURNING a.account_id,a.document_id,a.generation,a.attempt,a.workflow_id,a.run_id,a.delivery_deadline,a.lease_token,a.task_queue,a.latest_permit_end,a.status`, limit)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var p m.DocumentPendingJob
			p.UnlimitedInference = true
			if err = rows.Scan(&p.Job.AccountID, &p.Job.DocumentID, &p.Job.Generation, &p.Job.AIAttempt, &p.WorkflowID, &p.RunID, &p.DeliveryDeadline, &p.LeaseToken, &p.TaskQueue, &p.LatestPermitEnd, &p.State); err != nil {
				return err
			}
			out = append(out, p)
		}
		return rows.Err()
	})
	return out, err
}

func (s *DocumentDataSource) AIExecutionFacts(ctx context.Context, p m.DocumentPendingJob) (m.DocumentExecutionFacts, error) {
	var facts m.DocumentExecutionFacts
	err := s.database.QueryRow(ctx, "SELECT run_id,latest_permit_end IS NULL FROM document_ai_jobs WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND attempt=$4 AND lease_token=$5 AND closed_at IS NULL", p.Job.AccountID, p.Job.DocumentID, p.Job.Generation, p.Job.AIAttempt, p.LeaseToken).Scan(&facts.RunID, &facts.SafeMissing)
	return facts, staleError(err)
}
func (s *DocumentDataSource) AIResolveExecution(ctx context.Context, p m.DocumentPendingJob, command m.DocumentExecutionResolution) error {
	run, code := command.RunID, command.Outcome
	if code != "" && !m.ValidFailureCode(code) {
		return m.DocumentValidationError{Message: "invalid AI execution outcome"}
	}
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		var old string
		var safe bool
		err := tx.QueryRow(ctx, `SELECT run_id,latest_permit_end IS NULL FROM document_ai_jobs WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND attempt=$4 AND lease_token=$5 AND closed_at IS NULL FOR UPDATE NOWAIT`, p.Job.AccountID, p.Job.DocumentID, p.Job.Generation, p.Job.AIAttempt, p.LeaseToken).Scan(&old, &safe)
		if err != nil {
			var lockError *pgconn.PgError
			if errors.As(err, &lockError) && lockError.Code == "55P03" {
				return m.ErrConflict
			}
			return staleError(err)
		}
		if old != command.ExpectedRunID || (command.Close && command.Missing && !safe) {
			return m.ErrStaleJob
		}
		closed := command.Close
		_, err = tx.Exec(ctx, `UPDATE document_ai_jobs SET run_id=CASE WHEN $6='' THEN run_id ELSE $6 END,closed_at=CASE WHEN $7 THEN clock_timestamp() ELSE closed_at END,status=CASE WHEN $7 AND status IN ('queued','running') THEN 'failed' ELSE status END,failure_code=CASE WHEN $7 AND status IN ('queued','running') THEN $8 ELSE failure_code END,finished_at=CASE WHEN $7 THEN COALESCE(finished_at,clock_timestamp()) ELSE finished_at END,updated_at=CASE WHEN $7 THEN clock_timestamp() ELSE updated_at END,lease_token=NULL,lease_expires_at=NULL,next_check_at=clock_timestamp()+interval '5 seconds' WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND attempt=$4 AND lease_token=$5`, p.Job.AccountID, p.Job.DocumentID, p.Job.Generation, p.Job.AIAttempt, p.LeaseToken, run, closed, code)
		return err
	})
}

func readAIMaintenanceFacts(ctx context.Context, tx pgx.Tx) (m.DocumentAIMaintenanceFacts, error) {
	var facts m.DocumentAIMaintenanceFacts
	if err := tx.QueryRow(ctx, "SELECT ai_reschedule_revision,ai_reschedule_cutoff,ai_reschedule_cursor FROM document_processing_configuration WHERE id=true").Scan(&facts.Revision, &facts.Cutoff, &facts.Cursor); err != nil {
		return facts, err
	}
	if facts.Revision == nil || facts.Cutoff == nil {
		return facts, nil
	}
	var snapshot []byte
	if err := tx.QueryRow(ctx, "SELECT configuration FROM document_processing_configurations WHERE revision=$1", *facts.Revision).Scan(&snapshot); err != nil {
		return facts, err
	}
	if err := json.Unmarshal(snapshot, &facts.Configuration); err != nil {
		return facts, err
	}
	rows, err := tx.Query(ctx, "SELECT d.account_id,d.id,d.accepted_sequence,COALESCE((SELECT max(configuration_revision) FROM document_ai_jobs a WHERE a.account_id=d.account_id AND a.document_id=d.id),0) FROM documents d JOIN document_processing p ON p.account_id=d.account_id AND p.document_id=d.id WHERE d.accepted_sequence>$1 AND d.accepted_sequence<$2 ORDER BY d.accepted_sequence LIMIT 100", facts.Cursor, *facts.Cutoff)
	if err != nil {
		return facts, err
	}
	for rows.Next() {
		var candidate m.DocumentAIMaintenanceCandidate
		if err = rows.Scan(&candidate.AccountID, &candidate.DocumentID, &candidate.Sequence, &candidate.LatestConfigurationRevision); err != nil {
			rows.Close()
			return facts, err
		}
		facts.Candidates = append(facts.Candidates, candidate)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return facts, err
	}
	for i := range facts.Candidates {
		candidate := &facts.Candidates[i]
		candidate.Facts, err = readAIEnqueueFacts(ctx, tx, candidate.AccountID, candidate.DocumentID)
		if err != nil {
			return facts, err
		}
	}
	return facts, nil
}
func (s *DocumentDataSource) AIMaintenanceFacts(ctx context.Context) (m.DocumentAIMaintenanceFacts, error) {
	var facts m.DocumentAIMaintenanceFacts
	err := pgx.BeginTxFunc(ctx, s.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error { var err error; facts, err = readAIMaintenanceFacts(ctx, tx); return err })
	return facts, err
}
func (s *DocumentDataSource) MaintainAI(ctx context.Context, command m.DocumentAIMaintenanceCommand) error {
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		for _, candidate := range command.Expected.Candidates {
			var id string
			if err := tx.QueryRow(ctx, "SELECT id FROM documents WHERE account_id=$1 AND id=$2 FOR UPDATE NOWAIT", candidate.AccountID, candidate.DocumentID).Scan(&id); err != nil {
				if errors.Is(err, pgx.ErrNoRows) {
					return m.ErrConflict
				}
				return err
			}
			if _, err := tx.Exec(ctx, "SELECT id FROM document_ai_jobs WHERE account_id=$1 AND document_id=$2 AND status IN ('queued','running') FOR UPDATE NOWAIT", candidate.AccountID, candidate.DocumentID); err != nil {
				return err
			}
		}
		facts, err := readAIMaintenanceFacts(ctx, tx)
		if err != nil {
			return err
		}
		if !reflect.DeepEqual(facts, command.Expected) {
			return m.ErrConflict
		}
		for _, enqueue := range command.Enqueue {
			if _, err = enqueueAI(ctx, tx, enqueue.AccountID, enqueue.DocumentID, "", "configuration_change", enqueue.Command, ""); err != nil {
				return err
			}
		}
		_, err = tx.Exec(ctx, "UPDATE document_processing_configuration SET ai_reschedule_cursor=$1,ai_reschedule_revision=CASE WHEN $2 THEN NULL ELSE ai_reschedule_revision END,ai_reschedule_cutoff=CASE WHEN $2 THEN NULL ELSE ai_reschedule_cutoff END WHERE id=true", command.Cursor, command.Complete)
		return err
	})
	var lockError *pgconn.PgError
	if errors.As(err, &lockError) && lockError.Code == "55P03" {
		return m.ErrConflict
	}
	return err
}
