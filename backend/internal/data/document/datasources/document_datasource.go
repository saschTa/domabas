package datasources

import (
	"context"
	"crypto/cipher"

	"github.com/jackc/pgx/v5"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulermodels "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
)

type DocumentResourceScheduler interface {
	Reserve(context.Context, pgx.Tx, string, string, []string) (bool, error)
	ReserveFirst(context.Context, pgx.Tx, string, []schedulermodels.SchedulerAdmissionCandidate) (string, error)
}

type DocumentPublicationStore interface {
	Promote(context.Context, records.DocumentContentReference) (records.DocumentContentReference, error)
}

type DocumentDataSource struct {
	scheduler    DocumentResourceScheduler
	limits       records.DocumentIngestionLimits
	vault        cipher.AEAD
	dashboardURL string
	database     *postgres.PostgresDatabase
	publication  DocumentPublicationStore
}

func NewDocumentIngestionDataSource(database *postgres.PostgresDatabase, publication DocumentPublicationStore, scheduler DocumentResourceScheduler, dashboardURLs ...string) *DocumentDataSource {
	dashboard := ""
	if len(dashboardURLs) > 0 {
		dashboard = dashboardURLs[0]
	}
	return &DocumentDataSource{database: database, publication: publication, scheduler: scheduler, dashboardURL: dashboard}
}

func NewDocumentDataSource(database *postgres.PostgresDatabase) *DocumentDataSource {
	return &DocumentDataSource{database: database}
}
