package realtime

import (
	"context"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/data/realtime/datasources"
	"github.com/domabas/domabas/backend/internal/data/realtime/repos"
	"github.com/domabas/domabas/backend/internal/domain/realtime/interfaces"
	"github.com/domabas/domabas/backend/internal/domain/realtime/services"
	"github.com/domabas/domabas/backend/internal/presentation/realtime/handlers"
)

type RealtimeContainer struct {
	listener   *datasources.RealtimeNotificationDataSource
	supervisor *handlers.RealtimeSupervisor
}

func NewRealtimeContainer(ctx context.Context, database *postgres.PostgresDatabase, databaseURL string, auth interfaces.RealtimeAuthenticator, policy interfaces.RealtimePolicy, origins []string) (*RealtimeContainer, error) {
	listener, err := datasources.NewRealtimeNotificationDataSource(databaseURL)
	if err != nil {
		return nil, err
	}
	service := services.NewRealtimeService(repos.NewRealtimeAuthorityRepository(datasources.NewRealtimeAuthorityDataSource(database)), auth, policy)
	supervisor := handlers.NewRealtimeSupervisor(service, origins)
	if err = listener.Start(ctx, repos.NewRealtimeNotificationRepository(supervisor)); err != nil {
		supervisor.Close()
		return nil, err
	}
	return &RealtimeContainer{listener: listener, supervisor: supervisor}, nil
}
func (c *RealtimeContainer) Handler() *handlers.RealtimeHandler {
	return handlers.NewRealtimeHandler(c.supervisor)
}
func (c *RealtimeContainer) Ping(ctx context.Context) error { return c.supervisor.Ping(ctx) }
func (c *RealtimeContainer) Drain()                         { c.supervisor.Close() }
func (c *RealtimeContainer) Close()                         { c.supervisor.Close(); c.listener.Close() }
