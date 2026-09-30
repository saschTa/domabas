package datasources

import (
	"cmp"
	"context"
	"fmt"
	"slices"

	r "github.com/domabas/domabas/backend/internal/data/scheduler/models"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/jackc/pgx/v5"
)

func (s *SchedulerDataSource) Settings(ctx context.Context, actor m.SchedulerActor) (r.SchedulerSettingsRecord, error) {
	var settings r.SchedulerSettingsRecord
	err := s.settingsReadTx(ctx, actor, func(tx pgx.Tx) error {
		var err error
		settings, err = s.settings(ctx, tx)
		return err
	})
	return settings, err
}

func (s *SchedulerDataSource) UpdateSettings(ctx context.Context, actor m.SchedulerActor, plan m.SchedulerSettingsPlan) (r.SchedulerSettingsRecord, error) {
	var settings r.SchedulerSettingsRecord
	err := s.settingsTx(ctx, actor, func(tx pgx.Tx) error {
		var err error
		settings, err = s.settingsMetadata(ctx, tx)
		if err != nil {
			return err
		}
		if settings.Revision != plan.ExpectedRevision || settings.OllamaQueueSize != plan.ExpectedQueueSize || len(settings.Resources) != len(plan.ExpectedResources) {
			return m.ErrConflict
		}
		for i, resource := range settings.Resources {
			expected := plan.ExpectedResources[i]
			if resource.ID != expected.ID || resource.Label != expected.Label || resource.Limit != expected.Limit || resource.MaximumLimit != expected.MaximumLimit {
				return m.ErrConflict
			}
		}
		var added int64
		for _, resource := range plan.Materialize {
			tag, err := tx.Exec(ctx, "INSERT INTO scheduler_resources(id,label,origin,concurrency_limit) VALUES($1,$2,$2,$3) ON CONFLICT(id) DO NOTHING", resource.ID, resource.Label, resource.Limit)
			if err != nil {
				return err
			}
			added += tag.RowsAffected()
		}
		for _, resource := range plan.Changes {
			if _, err = tx.Exec(ctx, "UPDATE scheduler_resources SET concurrency_limit=$2 WHERE id=$1", resource.ID, resource.Limit); err != nil {
				return err
			}
		}
		if len(plan.Changes) > 0 {
			added++
		}
		if added > 0 {
			if _, err = tx.Exec(ctx, "UPDATE scheduler_settings SET revision=revision+$1 WHERE singleton", added); err != nil {
				return err
			}
		}
		settings, err = s.settings(ctx, tx)
		return err
	})
	return settings, err
}

func (s *SchedulerDataSource) settings(ctx context.Context, tx pgx.Tx) (r.SchedulerSettingsRecord, error) {
	settings, err := s.settingsMetadata(ctx, tx)
	if err != nil {
		return settings, err
	}
	rows, err := tx.Query(ctx, `SELECT rr.resource_id,count(*) FROM scheduler_requests q
 JOIN scheduler_request_resources rr ON rr.workflow_id=q.workflow_id
 WHERE q.state='active' AND NOT `+schedulerClosedExecution+` GROUP BY rr.resource_id`)
	if err != nil {
		return settings, err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var active int
		if err := rows.Scan(&id, &active); err != nil {
			return settings, err
		}
		for index := range settings.Resources {
			if settings.Resources[index].ID == id {
				settings.Resources[index].ActiveJobs = active
				break
			}
		}
	}
	return settings, rows.Err()
}

func (s *SchedulerDataSource) settingsMetadata(ctx context.Context, tx pgx.Tx) (r.SchedulerSettingsRecord, error) {
	settings := r.SchedulerSettingsRecord{Resources: []r.SchedulerResourceRecord{}, Pipelines: []r.SchedulerPipelineRecord{}}
	pipelines, defaults, err := s.pipelineResources(ctx, tx)
	if err != nil {
		return settings, err
	}
	settings.Pipelines = pipelines
	if err = tx.QueryRow(ctx, `SELECT revision,ollama_queue_size FROM scheduler_settings WHERE singleton`).Scan(&settings.Revision, &settings.OllamaQueueSize); err != nil {
		return settings, err
	}
	rows, err := tx.Query(ctx, `SELECT r.id,r.label,r.concurrency_limit FROM scheduler_resources r
 ORDER BY CASE r.id WHEN 'worker' THEN 0 WHEN 'ollama' THEN 1 ELSE 2 END,r.label,r.id`)
	if err != nil {
		return settings, err
	}
	defer rows.Close()
	for rows.Next() {
		resource := r.SchedulerResourceRecord{}
		if err = rows.Scan(&resource.ID, &resource.Label, &resource.Limit); err != nil {
			return settings, err
		}
		resource.MaximumLimit = m.SchedulerResourceMaximum(resource.ID, settings.OllamaQueueSize)
		settings.Resources = append(settings.Resources, resource)
	}
	if err := rows.Err(); err != nil {
		return settings, err
	}
	for _, resource := range defaults {
		if !slices.ContainsFunc(settings.Resources, func(v r.SchedulerResourceRecord) bool { return v.ID == resource.ID }) {
			settings.Resources = append(settings.Resources, resource)
		}
	}
	resourceOrder := func(id string) int {
		switch id {
		case "worker":
			return 0
		case "ollama":
			return 1
		default:
			return 2
		}
	}
	slices.SortFunc(settings.Resources, func(a, b r.SchedulerResourceRecord) int {
		return cmp.Or(cmp.Compare(resourceOrder(a.ID), resourceOrder(b.ID)), cmp.Compare(a.Label, b.Label), cmp.Compare(a.ID, b.ID))
	})
	return settings, nil
}

func (s *SchedulerDataSource) pipelineResources(ctx context.Context, tx pgx.Tx) ([]r.SchedulerPipelineRecord, []r.SchedulerResourceRecord, error) {
	var documentProvider, documentURL, chatProvider, chatURL string
	if err := tx.QueryRow(ctx, `SELECT scheduler_provider,scheduler_base_url FROM document_processing_configuration WHERE id=true`).Scan(&documentProvider, &documentURL); err != nil {
		return nil, nil, fmt.Errorf("read document workload resources: %w", err)
	}
	if err := tx.QueryRow(ctx, `SELECT CASE WHEN enabled THEN provider ELSE '' END,base_url FROM chat_configuration WHERE singleton`).Scan(&chatProvider, &chatURL); err != nil {
		return nil, nil, err
	}
	documentResources, documentDefaults, err := s.resourceRequirements(m.SchedulerConfiguredProviders(documentProvider, documentURL))
	if err != nil {
		return nil, nil, err
	}
	chatResources, chatDefaults, err := s.resourceRequirements(m.SchedulerConfiguredProviders(chatProvider, chatURL))
	if err != nil {
		return nil, nil, err
	}
	return schedulerPipelineRecordsMapper(m.SchedulerPipelineRequirements(documentResources, chatResources)), append(documentDefaults, chatDefaults...), nil
}
