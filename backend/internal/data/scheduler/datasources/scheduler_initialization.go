package datasources

import (
	"context"
	"encoding/json"
	"fmt"

	r "github.com/domabas/domabas/backend/internal/data/scheduler/models"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/jackc/pgx/v5"
)

func retainedProviders(execution r.SchedulerRetainedExecution) ([]string, error) {
	facts := m.SchedulerRetainedConfiguration{Pipeline: execution.Pipeline, Provider: execution.Provider, BaseURL: execution.BaseURL, Combined: execution.Combined, SnapshotPresent: len(execution.Configuration) > 0}
	if facts.SnapshotPresent && (execution.Pipeline == "document_ai" || execution.Combined) {
		var snapshot r.SchedulerRetainedSnapshot
		if err := json.Unmarshal(execution.Configuration, &snapshot); err != nil {
			return nil, fmt.Errorf("decode retained workload provider snapshot: %w", err)
		}
		facts.PropertiesEnabled = snapshot.LLM.Enabled
		facts.InvoicesEnabled = snapshot.LLM.Enabled
		if snapshot.LLM.InvoiceEnabled != nil {
			facts.InvoicesEnabled = *snapshot.LLM.InvoiceEnabled
		}
		facts.LLMProvider, facts.LLMBaseURL = snapshot.LLM.Provider, snapshot.LLM.BaseURL
	}
	return m.SchedulerRetainedProviders(facts)
}

func (s *SchedulerDataSource) Initialize(ctx context.Context) error {
	if s.queueSize < 2 {
		return fmt.Errorf("OLLAMA_MAX_QUEUE must be at least 2 for the shared 50%% workload budget")
	}
	if s.ollamaOrigin == "" {
		return fmt.Errorf("workload scheduler requires a valid internal Ollama origin")
	}
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if err := schedulerLock(ctx, tx); err != nil {
			return err
		}
		var initialized bool
		var queueSize int
		if err := tx.QueryRow(ctx, `SELECT initialized,ollama_queue_size FROM scheduler_settings WHERE singleton`).Scan(&initialized, &queueSize); err != nil {
			return err
		}
		if queueSize != s.queueSize {
			if _, err := tx.Exec(ctx, `UPDATE scheduler_settings SET ollama_queue_size=$1,revision=revision+1 WHERE singleton`, s.queueSize); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `UPDATE scheduler_resources SET concurrency_limit=LEAST(concurrency_limit,$1) WHERE id='ollama'`, m.SchedulerResourceMaximum("ollama", s.queueSize)); err != nil {
				return err
			}
		}
		if initialized {
			return reconcileScheduler(ctx, tx)
		}
		rows, err := tx.Query(ctx, `SELECT e.workflow_id,'document_ingestion','', '',j.configuration,NOT e.split_pipeline
 FROM document_processing_executions e LEFT JOIN document_processing_jobs j ON j.id=e.job_id WHERE e.closed_at IS NULL
 UNION ALL SELECT workflow_id,'document_ai','','',configuration,false FROM document_ai_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL
 UNION ALL SELECT workflow_id,'document_thumbnail','','',NULL::jsonb,false FROM document_thumbnail_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL
 UNION ALL SELECT workflow_id,'email','','',NULL::jsonb,false FROM email_executions WHERE closed_at IS NULL
 UNION ALL SELECT 'domabas-paperless-'||id::text,'paperless','','',NULL::jsonb,false FROM paperless_runs WHERE first_start_at IS NOT NULL AND NOT execution_closed
 UNION ALL SELECT workflow_id,'chat',provider,base_url,NULL::jsonb,false FROM chat_turns WHERE admitted_at IS NOT NULL AND NOT execution_closed`)
		if err != nil {
			return err
		}
		var executions []r.SchedulerRetainedExecution
		for rows.Next() {
			var execution r.SchedulerRetainedExecution
			if err := rows.Scan(&execution.WorkflowID, &execution.Pipeline, &execution.Provider, &execution.BaseURL, &execution.Configuration, &execution.Combined); err != nil {
				rows.Close()
				return err
			}
			executions = append(executions, execution)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return err
		}
		for _, execution := range executions {
			providers, err := retainedProviders(execution)
			blocksAdmission := err != nil
			for _, provider := range providers {
				if s.ResourceID(provider) == "" {
					blocksAdmission = true
				}
			}
			if blocksAdmission {
				providers = []string{"ollama"}
			}
			resources, err := s.requirements(ctx, tx, providers)
			if err != nil {
				return err
			}
			if err = putSchedulerRequest(ctx, tx, execution.WorkflowID, execution.Pipeline, resources, true); err != nil {
				return err
			}
			if blocksAdmission {
				if _, err = tx.Exec(ctx, `UPDATE scheduler_requests SET blocks_admission=true WHERE workflow_id=$1`, execution.WorkflowID); err != nil {
					return err
				}
			}
		}
		_, err = tx.Exec(ctx, `UPDATE scheduler_settings SET initialized=true WHERE singleton`)
		return err
	})
}
