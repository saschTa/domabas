package interfaces

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
)

type SchedulerRepository interface {
	Settings(context.Context, m.SchedulerActor) (m.SchedulerSettings, error)
	UpdateSettings(context.Context, m.SchedulerActor, m.SchedulerSettingsPlan) (m.SchedulerSettings, error)
}
