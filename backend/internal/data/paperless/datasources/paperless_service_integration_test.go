//go:build integration

package datasources

import (
	"testing"
	"time"

	identity "github.com/domabas/domabas/backend/internal/bootstrap/identity"
	"github.com/domabas/domabas/backend/internal/domain/paperless/services"
)

func paperlessService(t *testing.T, source *PaperlessJobsDataSource) *services.PaperlessJobsService {
	t.Helper()
	identities, err := identity.NewIdentityContainer(source.db, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	return services.NewPaperlessJobsService(source, nil, identities.Service())
}
