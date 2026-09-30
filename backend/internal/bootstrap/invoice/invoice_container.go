package invoice

import (
	"log/slog"

	"github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	"github.com/domabas/domabas/backend/internal/data/invoice/repos"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/domain/invoice/interfaces"
	"github.com/domabas/domabas/backend/internal/domain/invoice/services"
)

func NewInvoiceService(database *postgres.PostgresDatabase, authority interfaces.InvoiceAuthority, inference datasources.InvoiceInference, credentials interfaces.InvoiceCredentials, logger *slog.Logger) *services.InvoiceService {
	return services.NewInvoiceService(repos.NewInvoiceRepository(datasources.NewInvoiceDataSource(database)), datasources.NewInvoiceExtractorDataSource(inference, logger), credentials, authority, datasources.NewInvoiceClassifierDataSource(inference, logger))
}
