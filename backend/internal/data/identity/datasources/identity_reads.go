package datasources

import (
	"context"
	"github.com/jackc/pgx/v5"
)

func (source *IdentityDataSource) identityReadTransaction(ctx context.Context, fn func(pgx.Tx) error) error {
	return pgx.BeginTxFunc(ctx, source.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, fn)
}
