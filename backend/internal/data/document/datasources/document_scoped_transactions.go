package datasources

import (
	"context"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

func documentImportAuthority(ctx context.Context, tx pgx.Tx, a m.DocumentActor, lock bool) error {
	if a.ImportRunID == "" {
		return nil
	}
	suffix := ""
	if lock {
		suffix = " FOR UPDATE"
	}
	var active bool
	if err := tx.QueryRow(ctx, "SELECT state='running' AND NOT cancel_requested AND credential_revision=$4 FROM paperless_runs WHERE id=$1 AND account_id=$2 AND owner_id=$3"+suffix, a.ImportRunID, a.AccountID, a.UserID, a.CredentialRevision).Scan(&active); err != nil {
		return authorityError(err)
	}
	if !active || a.ImportClaimToken == "" || a.ImportSourceID < 1 {
		return m.ErrForbidden
	}
	if err := tx.QueryRow(ctx, "SELECT COALESCE(status='pending' AND claim_token=$3::uuid AND claim_deadline>clock_timestamp(),false) FROM paperless_items WHERE run_id=$1 AND source_id=$2"+suffix, a.ImportRunID, a.ImportSourceID, a.ImportClaimToken).Scan(&active); err != nil {
		return authorityError(err)
	}
	if !active {
		return m.ErrStaleJob
	}
	return nil
}
func authorityError(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return m.ErrUnauthorized
	}
	return err
}
func documentError(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return m.ErrNotFound
	}
	var pg *pgconn.PgError
	if errors.As(err, &pg) {
		if pg.Code == "23505" && pg.ConstraintName == "document_files_account_id_sha256_key" {
			return m.ErrDuplicate
		}
		if pg.Code == "57014" || pg.Code == "40001" || pg.Code == "40P01" || pg.Code == "55P03" {
			return m.ErrUnavailable
		}
	}
	return err
}
func (s *DocumentDataSource) scopedWriteTx(ctx context.Context, a m.DocumentActor, fn func(pgx.Tx) error) error {
	return documentError(pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='5s'"); err != nil {
			return err
		}
		if err := documentImportAuthority(ctx, tx, a, true); err != nil {
			return err
		}
		return fn(tx)
	}))
}
func (s *DocumentDataSource) scopedReadTx(ctx context.Context, a m.DocumentActor, fn func(pgx.Tx) error) error {
	return documentError(pgx.BeginTxFunc(ctx, s.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		if err := documentImportAuthority(ctx, tx, a, false); err != nil {
			return err
		}
		return fn(tx)
	}))
}
