//go:build integration

package repos

import (
	"context"
	"testing"
	"time"

	identity "github.com/domabas/domabas/backend/internal/bootstrap/identity"
	email "github.com/domabas/domabas/backend/internal/data/email/datasources"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	p "github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/domabas/domabas/backend/internal/domain/email/services"
	"github.com/jackc/pgx/v5/pgxpool"
)

func independentEmailAuthority(t *testing.T, pool *pgxpool.Pool) p.EmailAuthority {
	t.Helper()
	db, err := postgres.NewPostgresDataSource(t.Context(), pool.Config().ConnString())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(db.Close)
	identities, err := identity.NewIdentityContainer(db.Database(), time.Now)
	if err != nil {
		t.Fatal(err)
	}
	return identities.Service()
}

func independentEmailService(t *testing.T, pool *pgxpool.Pool, repository *EmailRepository) *services.EmailService {
	return services.NewEmailService(repository, nil, true, independentEmailAuthority(t, pool))
}

func independentPollingService(t *testing.T, pool *pgxpool.Pool, source *email.EmailDataSource, repository *EmailRepository) *services.EmailPollingService {
	polling := NewEmailPollingRepository(source, repository.vault)
	return services.NewEmailPollingService(polling, polling, nil, nil, time.Now, independentEmailAuthority(t, pool))
}

type independentEmailScheduling struct {
	p.EmailDispatchRepository
	source *email.EmailDataSource
	keys   []string
}

func (s independentEmailScheduling) ScheduleCandidates(ctx context.Context) ([]m.EmailScheduleCandidate, error) {
	return s.source.ScheduleCandidates(ctx, s.keys...)
}
func (s independentEmailScheduling) ScheduleProvider(ctx context.Context, c m.EmailScheduleCandidate, trigger string) error {
	return s.source.ScheduleProvider(ctx, c, trigger, s.keys...)
}
func independentSchedule(t *testing.T, pool *pgxpool.Pool, source *email.EmailDataSource, repository *EmailRepository, keys ...string) error {
	polling := NewEmailPollingRepository(source, repository.vault)
	service := services.NewEmailPollingService(polling, independentEmailScheduling{EmailDispatchRepository: polling, source: source, keys: keys}, nil, nil, time.Now, independentEmailAuthority(t, pool))
	return service.Schedule(t.Context())
}
