package datasources

import (
	"context"
	"errors"
	"fmt"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	schedulermodels "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/jackc/pgx/v5"
)

func (s *DocumentDataSource) DeliverySettings(context.Context) (m.DocumentDeliverySettings, error) {
	return m.DocumentDeliverySettings{UnlimitedInference: s.limits.UnlimitedInference}, nil
}

func (s *DocumentDataSource) ClaimRecords(ctx context.Context, limit int, lease time.Duration, commands []m.DocumentReindexScheduleCommand, policy m.DocumentDeliveryPolicy, queues ...string) ([]r.DocumentLeaseRecord, error) {
	result := []r.DocumentLeaseRecord{}
	queue := "domabas-documents"
	if len(queues) > 0 && queues[0] != "" {
		queue = queues[0]
	}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		c, err := readConfiguration(ctx, tx)
		if err != nil {
			return err
		}
		var legacy bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM document_processing_executions WHERE closed_at IS NULL AND legacy)`).Scan(&legacy); err != nil {
			return err
		}
		if !policy.WaitForLegacy || !legacy {
			if err = s.admitDocument(ctx, tx, c, queue, policy, commands); err != nil {
				return err
			}
		}
		var row r.DocumentLeaseRecord
		err = tx.QueryRow(ctx, `WITH candidate AS(SELECT account_id,document_id,generation FROM document_processing_executions WHERE closed_at IS NULL AND NOT legacy AND run_id='' AND delivery_deadline>clock_timestamp() AND (start_retry_until IS NULL OR start_retry_until>clock_timestamp()) AND next_check_at<=clock_timestamp() AND (lease_expires_at IS NULL OR lease_expires_at<=clock_timestamp()) ORDER BY admitted_at LIMIT 1 FOR UPDATE) UPDATE document_processing_executions e SET first_permit_at=COALESCE(first_permit_at,clock_timestamp()),start_retry_until=COALESCE(start_retry_until,LEAST(delivery_deadline,clock_timestamp()+$1::interval)),latest_permit_end=LEAST(clock_timestamp()+$2::interval,delivery_deadline,COALESCE(start_retry_until,clock_timestamp()+$1::interval)),lease_token=gen_random_uuid(),lease_expires_at=clock_timestamp()+$3::interval,next_check_at=clock_timestamp()+$3::interval FROM candidate c WHERE e.account_id=c.account_id AND e.document_id=c.document_id AND e.generation=c.generation RETURNING COALESCE(e.outbox_id::text,''),e.lease_token,e.account_id,e.document_id,e.generation,e.delivery_deadline,e.workflow_id,e.task_queue,e.run_id,e.latest_permit_end,e.execution_timeout_seconds=0,e.split_pipeline`, policy.StartRetryWindow.String(), policy.StartPermit.String(), policy.ClaimLease.String()).Scan(&row.ID, &row.LeaseToken, &row.Job.AccountID, &row.Job.DocumentID, &row.Job.Generation, &row.DeliveryDeadline, &row.WorkflowID, &row.TaskQueue, &row.RunID, &row.PermitEnd, &row.UnlimitedInference, &row.SplitPipeline)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, `UPDATE document_outbox SET lease_token=$2,lease_expires_at=clock_timestamp()+$3::interval WHERE id=NULLIF($1,'')::uuid`, row.ID, row.LeaseToken, policy.ClaimLease.String()); err != nil {
			return err
		}
		result = append(result, row)
		return nil
	})
	return result, err
}
func (s *DocumentDataSource) admitDocument(ctx context.Context, tx pgx.Tx, c m.DocumentProcessingConfiguration, queue string, policy m.DocumentDeliveryPolicy, commands []m.DocumentReindexScheduleCommand) error {
	var err error
	var last string
	if err = tx.QueryRow(ctx, `SELECT last_class FROM document_processing_admission WHERE id=true FOR UPDATE`).Scan(&last); err != nil {
		return err
	}
	var row *r.DocumentLeaseRecord
	var batch string
	ordinary := func(enrolled bool) (*r.DocumentLeaseRecord, string, error) {
		v := &r.DocumentLeaseRecord{}
		var parentBatch string
		err := tx.QueryRow(ctx, `SELECT o.id,o.account_id,o.document_id,o.generation,o.configuration_revision,COALESCE(p.parent_batch_id::text,'')
 FROM document_outbox o JOIN document_processing p ON p.account_id=o.account_id AND p.document_id=o.document_id AND p.generation=o.generation
 JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id AND d.ocr_revision=p.ocr_revision
 LEFT JOIN scheduler_requests q ON q.workflow_id=(CASE WHEN p.split_pipeline THEN 'document-ingestion-v2/' ELSE 'document-ingestion-v1/' END)||p.account_id::text||'/'||p.document_id::text||'/'||p.generation::text AND q.state='waiting'
 WHERE o.acknowledged_at IS NULL AND o.delivery_deadline IS NULL AND o.available_at<=clock_timestamp() AND p.state IN ('queued','processing')
 AND (NOT $1::boolean OR q.workflow_id IS NOT NULL)
 AND NOT EXISTS(SELECT 1 FROM document_processing_executions e WHERE e.account_id=o.account_id AND e.document_id=o.document_id AND e.closed_at IS NULL)
 ORDER BY q.sequence NULLS LAST,o.available_at,o.id LIMIT 1 FOR UPDATE OF d SKIP LOCKED`, enrolled).Scan(&v.ID, &v.Job.AccountID, &v.Job.DocumentID, &v.Job.Generation, &v.ConfigurationRevision, &parentBatch)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, "", nil
		}
		return v, parentBatch, err
	}
	if policy.PrioritizeEnrolled {
		row, batch, err = ordinary(true)
	}
	if err != nil {
		return err
	}
	if row == nil {
		if policy.AlternateReindex && last == "ordinary" {
			row, batch, err = scheduleReindex(ctx, tx, commands)
			if err == nil && row == nil {
				row, batch, err = ordinary(false)
			}
		} else {
			row, batch, err = ordinary(false)
			if err == nil && row == nil {
				row, batch, err = scheduleReindex(ctx, tx, commands)
			}
		}
	}
	if err != nil {
		return err
	}
	if row == nil {
		return nil
	}
	var split bool
	if err = tx.QueryRow(ctx, "SELECT split_pipeline FROM document_processing WHERE account_id=$1 AND document_id=$2 AND generation=$3", row.Job.AccountID, row.Job.DocumentID, row.Job.Generation).Scan(&split); err != nil {
		return err
	}
	prefix := "document-ingestion-v1"
	if split {
		prefix = "document-ingestion-v2"
	}
	workflow := fmt.Sprintf(prefix+"/%s/%s/%d", row.Job.AccountID, row.Job.DocumentID, row.Job.Generation)
	providers := []string{"ollama"}
	if !split {
		var provider, endpoint string
		if err = tx.QueryRow(ctx, "SELECT scheduler_provider,scheduler_base_url FROM document_processing_jobs WHERE account_id=$1 AND document_id=$2 AND generation=$3", row.Job.AccountID, row.Job.DocumentID, row.Job.Generation).Scan(&provider, &endpoint); err != nil {
			return err
		}
		if provider == "openai" {
			providers = append(providers, endpoint)
		}
	}
	if s.scheduler == nil {
		return errors.New("document resource scheduler is not configured")
	}
	admitted, err := s.scheduler.ReserveFirst(ctx, tx, "document_ingestion", []schedulermodels.SchedulerAdmissionCandidate{{WorkflowID: workflow, Providers: providers}})
	if err != nil || admitted == "" {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE document_processing SET delivery_deadline=clock_timestamp()+$5::interval,unlimited_inference=$4 WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND delivery_deadline IS NULL`, row.Job.AccountID, row.Job.DocumentID, row.Job.Generation, policy.ExecutionTimeout == 0, policy.DeliveryWindow.String()); err != nil {
		return err
	}
	if err = tx.QueryRow(ctx, `UPDATE document_outbox o SET delivery_deadline=p.delivery_deadline FROM document_processing p WHERE o.id=$1 AND p.account_id=o.account_id AND p.document_id=o.document_id AND p.generation=o.generation RETURNING o.delivery_deadline`, row.ID).Scan(&row.DeliveryDeadline); err != nil {
		return err
	}

	if _, err = tx.Exec(ctx, `INSERT INTO document_processing_executions(account_id,document_id,generation,outbox_id,job_id,workflow_id,task_queue,admitted_at,delivery_deadline,execution_timeout_seconds,split_pipeline) SELECT $1,$2,$3,$4,j.id,$5,$6,clock_timestamp(),$7,$8,$9 FROM document_processing_jobs j WHERE j.account_id=$1 AND j.document_id=$2 AND j.generation=$3`, row.Job.AccountID, row.Job.DocumentID, row.Job.Generation, row.ID, workflow, queue, row.DeliveryDeadline, int64(policy.ExecutionTimeout/time.Second), split); err != nil {
		return err
	}
	class := "ordinary"
	if batch != "" {
		class = "reindex"
	}
	if _, err = tx.Exec(ctx, `UPDATE document_processing_admission SET last_class=$1,last_batch_id=NULLIF($2,'')::uuid WHERE id=true`, class, batch); err != nil {
		return err
	}
	return nil
}

func (s *DocumentDataSource) Acknowledge(ctx context.Context, l m.DocumentOutboxLease, workflow, run string) error {
	prefix := "document-ingestion-v1"
	if l.SplitPipeline {
		prefix = "document-ingestion-v2"
	}
	expected := fmt.Sprintf(prefix+"/%s/%s/%d", l.Job.AccountID, l.Job.DocumentID, l.Job.Generation)
	if workflow != expected || run == "" {
		return m.ErrStaleJob
	}
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE document_processing_executions SET run_id=$5,lease_token=NULL,lease_expires_at=NULL,next_check_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND lease_token=$4 AND closed_at IS NULL AND (run_id='' OR run_id=$5)`, l.Job.AccountID, l.Job.DocumentID, l.Job.Generation, l.LeaseToken, run)
		if err != nil {
			return err
		}
		if tag.RowsAffected() != 1 {
			return m.ErrStaleJob
		}
		var id string
		err = tx.QueryRow(ctx, `SELECT id FROM documents WHERE account_id=$1 AND id=$2 FOR UPDATE`, l.Job.AccountID, l.Job.DocumentID).Scan(&id)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, `UPDATE document_processing SET workflow_id=$4,run_id=$5,processing_deadline=CASE WHEN unlimited_inference THEN NULL ELSE COALESCE(processing_deadline,clock_timestamp()+(SELECT execution_timeout_seconds FROM document_processing_executions WHERE account_id=$1 AND document_id=$2 AND generation=$3)*interval '1 second') END,processing_started_at=COALESCE(processing_started_at,clock_timestamp()),next_check_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND state IN ('queued','processing') AND (delivery_deadline>clock_timestamp() OR processing_started_at IS NOT NULL) AND (processing_deadline IS NULL OR processing_deadline>clock_timestamp())`, l.Job.AccountID, l.Job.DocumentID, l.Job.Generation, workflow, run); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE document_outbox SET acknowledged_at=clock_timestamp(),lease_token=NULL,lease_expires_at=NULL WHERE id=NULLIF($1,'')::uuid AND account_id=$2 AND document_id=$3 AND generation=$4`, l.ID, l.Job.AccountID, l.Job.DocumentID, l.Job.Generation)
		return err
	})
}
func (s *DocumentDataSource) Release(ctx context.Context, l m.DocumentOutboxLease, next time.Time) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE document_processing_executions SET lease_token=NULL,lease_expires_at=NULL,next_check_at=$5 WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND lease_token=$4 AND closed_at IS NULL`, l.Job.AccountID, l.Job.DocumentID, l.Job.Generation, l.LeaseToken, next)
		if err == nil && tag.RowsAffected() != 1 {
			return m.ErrStaleJob
		}
		return err
	})
}
func (s *DocumentDataSource) PendingRecords(ctx context.Context, limit int) ([]r.DocumentPendingRecord, error) {
	if limit < 1 || limit > 100 {
		limit = 20
	}
	out := []r.DocumentPendingRecord{}
	if err := s.expireProcessing(ctx); err != nil {
		return out, err
	}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `WITH candidates AS(SELECT account_id,document_id,generation FROM document_processing_executions WHERE closed_at IS NULL AND next_check_at<=clock_timestamp() AND (lease_expires_at IS NULL OR lease_expires_at<=clock_timestamp()) ORDER BY next_check_at,admitted_at LIMIT $1 FOR UPDATE) UPDATE document_processing_executions e SET lease_token=gen_random_uuid(),lease_expires_at=clock_timestamp()+interval '30 seconds',next_check_at=clock_timestamp()+interval '15 seconds' FROM candidates c WHERE e.account_id=c.account_id AND e.document_id=c.document_id AND e.generation=c.generation RETURNING e.account_id,e.document_id,e.generation,e.workflow_id,e.run_id,e.delivery_deadline,e.lease_token,e.task_queue,e.latest_permit_end,e.legacy,(SELECT processing_deadline FROM document_processing p WHERE p.account_id=e.account_id AND p.document_id=e.document_id AND p.generation=e.generation),COALESCE((SELECT state FROM document_processing p WHERE p.account_id=e.account_id AND p.document_id=e.document_id AND p.generation=e.generation),'superseded'),e.execution_timeout_seconds=0,e.split_pipeline`, limit)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var v r.DocumentPendingRecord
			if err = rows.Scan(&v.Job.AccountID, &v.Job.DocumentID, &v.Job.Generation, &v.WorkflowID, &v.RunID, &v.DeliveryDeadline, &v.LeaseToken, &v.TaskQueue, &v.LatestPermitEnd, &v.Legacy, &v.ProcessingDeadline, &v.State, &v.UnlimitedInference, &v.SplitPipeline); err != nil {
				return err
			}
			out = append(out, v)
		}
		return rows.Err()
	})
	return out, err
}
func (s *DocumentDataSource) ExecutionFacts(ctx context.Context, p m.DocumentPendingJob) (m.DocumentExecutionFacts, error) {
	var facts m.DocumentExecutionFacts
	err := s.database.QueryRow(ctx, "SELECT run_id,latest_permit_end IS NULL OR (execution_timeout_seconds>0 AND latest_permit_end+execution_timeout_seconds*interval '1 second'<=clock_timestamp()) FROM document_processing_executions WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND lease_token=$4 AND closed_at IS NULL", p.Job.AccountID, p.Job.DocumentID, p.Job.Generation, p.LeaseToken).Scan(&facts.RunID, &facts.SafeMissing)
	return facts, staleError(err)
}
func (s *DocumentDataSource) ResolveExecution(ctx context.Context, p m.DocumentPendingJob, command m.DocumentExecutionResolution) error {
	run, code := command.RunID, command.Outcome
	if code != "" && !m.ValidFailureCode(code) {
		return m.DocumentValidationError{Message: "invalid execution outcome"}
	}
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		var currentRun string
		var safeMissing bool
		err := tx.QueryRow(ctx, `SELECT run_id,latest_permit_end IS NULL OR (execution_timeout_seconds>0 AND latest_permit_end+execution_timeout_seconds*interval '1 second'<=clock_timestamp()) FROM document_processing_executions WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND lease_token=$4 AND closed_at IS NULL FOR UPDATE`, p.Job.AccountID, p.Job.DocumentID, p.Job.Generation, p.LeaseToken).Scan(&currentRun, &safeMissing)
		if err != nil {
			return staleError(err)
		}
		if currentRun != command.ExpectedRunID || (command.Close && command.Missing && !safeMissing) {
			return m.ErrStaleJob
		}
		close := command.Close
		if close {
			var id string
			err = tx.QueryRow(ctx, `SELECT id FROM documents WHERE account_id=$1 AND id=$2 FOR UPDATE`, p.Job.AccountID, p.Job.DocumentID).Scan(&id)
			if err != nil && !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			if err == nil {
				if _, err = tx.Exec(ctx, `UPDATE document_processing SET state='failed',stage='failed',failure_code=$4,updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND state IN ('queued','processing')`, p.Job.AccountID, p.Job.DocumentID, p.Job.Generation, code); err != nil {
					return err
				}
			}
			if _, err = tx.Exec(ctx, `UPDATE document_processing_jobs SET status='failed',failure_code=$4,finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND status IN ('queued','running')`, p.Job.AccountID, p.Job.DocumentID, p.Job.Generation, code); err != nil {
				return err
			}
		}
		_, err = tx.Exec(ctx, `UPDATE document_processing_executions SET run_id=CASE WHEN $5='' THEN run_id ELSE $5 END,task_queue=CASE WHEN task_queue='' THEN $6 ELSE task_queue END,closed_at=CASE WHEN $7 THEN clock_timestamp() ELSE closed_at END,lease_token=NULL,lease_expires_at=NULL,next_check_at=clock_timestamp()+interval '5 seconds' WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND lease_token=$4`, p.Job.AccountID, p.Job.DocumentID, p.Job.Generation, p.LeaseToken, run, p.TaskQueue, close)
		return err
	})
}
func (s *DocumentDataSource) FailExpired(ctx context.Context, j m.DocumentJob, code string) error {
	if code != "processing_timeout" && code != "delivery_timeout" {
		return m.DocumentValidationError{Message: "invalid deadline failure"}
	}
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := lockDocument(ctx, tx, j.AccountID, j.DocumentID); err != nil {
			return staleError(err)
		}
		tag, err := tx.Exec(ctx, `UPDATE document_processing SET state='failed',stage='failed',failure_code=$4,updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND state IN ('queued','processing') AND (($4='processing_timeout' AND processing_deadline<=clock_timestamp()) OR ($4='delivery_timeout' AND processing_deadline IS NULL AND processing_started_at IS NULL AND delivery_deadline<=clock_timestamp()))`, j.AccountID, j.DocumentID, j.Generation, code)
		if err == nil && tag.RowsAffected() != 1 {
			return m.ErrStaleJob
		}
		return err
	})
}

func (s *DocumentDataSource) expireProcessing(ctx context.Context) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `WITH expired AS(SELECT p.account_id,p.document_id,p.generation FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id WHERE p.state IN ('queued','processing') AND (p.processing_deadline<=clock_timestamp() OR (p.processing_deadline IS NULL AND p.processing_started_at IS NULL AND p.delivery_deadline<=clock_timestamp())) ORDER BY p.document_id LIMIT 100 FOR UPDATE OF d SKIP LOCKED) UPDATE document_processing p SET state='failed',stage='failed',failure_code=CASE WHEN processing_deadline IS NULL THEN 'delivery_timeout' ELSE 'processing_timeout' END,updated_at=clock_timestamp() FROM expired e WHERE p.account_id=e.account_id AND p.document_id=e.document_id AND p.generation=e.generation AND p.state IN ('queued','processing')`)
		return err
	})
}
