package datasources

import "github.com/domabas/domabas/backend/internal/data/postgres"

type IdentityDataSource struct {
	database *postgres.PostgresDatabase
}

func NewIdentityDataSource(database *postgres.PostgresDatabase) *IdentityDataSource {
	return &IdentityDataSource{database: database}
}
