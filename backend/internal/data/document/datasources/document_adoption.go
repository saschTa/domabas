package datasources

import (
	"context"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres/generated/table"
	jet "github.com/go-jet/jet/v2/postgres"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (source *DocumentDataSource) AdoptLegacyDocuments(ctx context.Context, accountID string) (int64, error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	account, err := uuid.Parse(accountID)
	if err != nil {
		return 0, err
	}
	var affected int64
	err = pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout = '5s'"); err != nil {
			return err
		}
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		accounts := table.Accounts.FromSchema("")
		query, args := jet.SELECT(accounts.ID).FROM(accounts).WHERE(accounts.ID.EQ(jet.UUID(account))).FOR(jet.UPDATE()).Sql()
		var locked uuid.UUID
		if err := tx.QueryRow(ctx, query, args...).Scan(&locked); err != nil {
			return err
		}
		d := table.Documents.FromSchema("")
		sql, args := d.UPDATE(d.AccountID).SET(jet.UUID(account)).WHERE(d.AccountID.IS_NULL()).Sql()
		result, err := tx.Exec(ctx, sql, args...)
		affected = result.RowsAffected()
		return err
	})
	return affected, err
}
