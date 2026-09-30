package datasources

import (
	"context"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/jackc/pgx/v5"
)

func (s *PaperlessJobsDataSource) settingsTx(ctx context.Context, actor d.DocumentActor, fn func(pgx.Tx) error) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='5s'"); err != nil {
			return err
		}
		return fn(tx)
	})
}

func (s *PaperlessJobsDataSource) Settings(ctx context.Context, actor d.DocumentActor) (m.PaperlessSettings, error) {
	var settings m.PaperlessSettings
	err := s.readTx(ctx, actor, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, "SELECT retrieval_concurrency,settings_revision FROM paperless_admission WHERE singleton").Scan(&settings.RetrievalConcurrency, &settings.Revision)
	})
	return settings, err
}

func (s *PaperlessJobsDataSource) UpdateSettings(ctx context.Context, actor d.DocumentActor, update m.PaperlessSettingsUpdate) (m.PaperlessSettings, error) {
	var settings m.PaperlessSettings
	err := s.settingsTx(ctx, actor, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, "SELECT retrieval_concurrency,settings_revision FROM paperless_admission WHERE singleton FOR UPDATE").Scan(&settings.RetrievalConcurrency, &settings.Revision); err != nil {
			return err
		}
		if settings.Revision != update.ExpectedRevision {
			return d.ErrConflict
		}
		if settings.RetrievalConcurrency == update.RetrievalConcurrency {
			return nil
		}
		return tx.QueryRow(ctx, "UPDATE paperless_admission SET retrieval_concurrency=$1,settings_revision=settings_revision+1 WHERE singleton RETURNING retrieval_concurrency,settings_revision", update.RetrievalConcurrency).Scan(&settings.RetrievalConcurrency, &settings.Revision)
	})
	return settings, err
}
