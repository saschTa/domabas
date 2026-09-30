package scheduler

import (
	"context"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/data/scheduler/datasources"
	"github.com/domabas/domabas/backend/internal/data/scheduler/repos"
	"github.com/domabas/domabas/backend/internal/domain/scheduler/interfaces"
	"github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/domabas/domabas/backend/internal/domain/scheduler/services"
	"github.com/domabas/domabas/backend/internal/presentation/scheduler/handlers"
	"github.com/jackc/pgx/v5"
)

type SchedulerAdmission interface {
	Reserve(context.Context, pgx.Tx, string, string, []string) (bool, error)
	ReserveFirst(context.Context, pgx.Tx, string, []models.SchedulerAdmissionCandidate) (string, error)
	ResourceID(string) string
}

type SchedulerContainer struct {
	source  *datasources.SchedulerDataSource
	service *services.SchedulerService
}

func NewSchedulerContainer(ctx context.Context, db *postgres.PostgresDatabase, authority interfaces.SchedulerAuthority, queueSize int, ollamaOrigin string) (*SchedulerContainer, error) {
	source := datasources.NewSchedulerDataSource(db, queueSize, ollamaOrigin)
	if err := source.Initialize(ctx); err != nil {
		return nil, err
	}
	return &SchedulerContainer{source: source, service: services.NewSchedulerService(repos.NewSchedulerRepository(source), authority)}, nil
}

func (c *SchedulerContainer) Service() *services.SchedulerService { return c.service }
func (c *SchedulerContainer) Admission() SchedulerAdmission       { return c.source }
func (c *SchedulerContainer) Handler() *handlers.SchedulerHandler {
	return handlers.NewSchedulerHandler(c.service)
}
