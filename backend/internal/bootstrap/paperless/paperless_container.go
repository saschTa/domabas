package paperless

import (
	"context"

	"github.com/domabas/domabas/backend/internal/data/paperless/datasources"
	"github.com/domabas/domabas/backend/internal/data/paperless/repos"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/domain/paperless/interfaces"
	"github.com/domabas/domabas/backend/internal/domain/paperless/services"
)

func NewPaperlessJobsService(ctx context.Context, db *postgres.PostgresDatabase, authority interfaces.PaperlessAuthority, key, keyFile, queue string, documents interfaces.PaperlessDocumentImporter, scheduler datasources.PaperlessResourceScheduler) (*services.PaperlessJobsService, error) {
	key, err := datasources.CredentialKey(ctx, db, key, keyFile)
	if err != nil {
		return nil, err
	}
	source := datasources.NewPaperlessRemoteDataSource()
	jobs, err := datasources.NewPaperlessJobsDataSource(db, key, queue, scheduler)
	if err != nil {
		return nil, err
	}
	return services.NewPaperlessJobsService(jobs, services.NewPaperlessImportService(repos.NewPaperlessRepository(source), documents), authority), nil
}
