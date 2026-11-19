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
			if resource.ID == "stage:paperless" {
				if _, err = tx.Exec(ctx, "UPDATE paperless_admission SET retrieval_concurrency=$1,settings_revision=settings_revision+1 WHERE singleton", resource.Limit); err != nil {
					return err
				}
				continue
			}
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
	rows, err := tx.Query(ctx, `WITH slots AS (
 SELECT q.pipeline, rr.resource_id FROM scheduler_requests q
 JOIN scheduler_request_resources rr USING(workflow_id)
 WHERE q.state='active' AND NOT `+schedulerClosedExecution+`
 UNION ALL
 SELECT CASE p.scope WHEN 'pipeline:invoice/inference' THEN 'invoice'
                     WHEN 'pipeline:tags/inference' THEN 'tags' ELSE q.pipeline END, p.resource_id
 FROM scheduler_step_permits p JOIN scheduler_requests q USING(workflow_id)
 UNION ALL
 SELECT 'paperless','stage:paperless' FROM paperless_items WHERE claim_token IS NOT NULL
 ) SELECT pipeline,resource_id,count(*) FROM slots GROUP BY pipeline,resource_id ORDER BY pipeline,resource_id`)
	if err != nil {
		return settings, err
	}
	defer rows.Close()
	pipelines := make(map[string]*r.SchedulerPipelineRecord, len(settings.Pipelines))
	for i := range settings.Pipelines {
		p := &settings.Pipelines[i]
		pipelines[p.ID] = p
		p.ActiveSlots = make(map[string]int, len(p.ResourceIDs))
		for _, id := range p.ResourceIDs {
			p.ActiveSlots[id] = 0
		}
	}
	resources := make(map[string]*r.SchedulerResourceRecord, len(settings.Resources))
	for i := range settings.Resources {
		resources[settings.Resources[i].ID] = &settings.Resources[i]
	}
	for rows.Next() {
		var pipeline, id string
		var active int
		if err := rows.Scan(&pipeline, &id, &active); err != nil {
			return settings, err
		}
		if resource := resources[id]; resource != nil {
			resource.ActiveJobs += active
		}
		if p := pipelines[pipeline]; p != nil && id != "pipeline:"+pipeline {
			if _, configured := p.ActiveSlots[id]; !configured {
				p.ResourceIDs = append(p.ResourceIDs, id)
			}
			p.ActiveSlots[id] = active
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
	rows, err := tx.Query(ctx, `SELECT r.id,r.label,r.concurrency_limit FROM (SELECT id,label,concurrency_limit FROM scheduler_resources UNION ALL SELECT 'stage:paperless','Paperless downloads',retrieval_concurrency FROM paperless_admission WHERE singleton) r
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
