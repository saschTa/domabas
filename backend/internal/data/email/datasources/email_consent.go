package datasources

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

func (s *EmailDataSource) Consent(ctx context.Context, id string) (m.EmailProvider, error) {
	var provider m.EmailProvider
	err := s.database.QueryRow(ctx, `SELECT p.id::text,p.account_id::text,p.owner_id::text,p.enabled,COALESCE(p.consent_revision,0) FROM email_providers p JOIN email_runs r ON r.provider_id=p.id WHERE r.id=$1 AND p.deleted_at IS NULL AND p.revision=r.provider_revision AND p.source_generation=r.source_generation`, id).Scan(&provider.ID, &provider.AccountID, &provider.OwnerID, &provider.Enabled, &provider.ConsentRevision)
	return provider, translate(err)
}
