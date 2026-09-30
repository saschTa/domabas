package repos

import (
	"context"
	r "github.com/domabas/domabas/backend/internal/data/scheduler/models"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
)

type SchedulerSource interface {
	Settings(context.Context, m.SchedulerActor) (r.SchedulerSettingsRecord, error)
	UpdateSettings(context.Context, m.SchedulerActor, m.SchedulerSettingsPlan) (r.SchedulerSettingsRecord, error)
}

type SchedulerRepository struct{ source SchedulerSource }

func NewSchedulerRepository(source SchedulerSource) *SchedulerRepository {
	return &SchedulerRepository{source: source}
}

func (r *SchedulerRepository) Settings(ctx context.Context, actor m.SchedulerActor) (m.SchedulerSettings, error) {
	settings, err := r.source.Settings(ctx, actor)
	return schedulerSettingsMapper(settings), err
}

func (r *SchedulerRepository) UpdateSettings(ctx context.Context, actor m.SchedulerActor, update m.SchedulerSettingsPlan) (m.SchedulerSettings, error) {
	settings, err := r.source.UpdateSettings(ctx, actor, update)
	return schedulerSettingsMapper(settings), err
}
