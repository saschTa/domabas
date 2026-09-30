package datasources

import (
	"context"

	"github.com/jackc/pgx/v5"
)

func (s *EmailDataSource) Cleanup(ctx context.Context) error {
	return s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		statements := []string{
			`WITH selected AS(SELECT id FROM email_providers p WHERE deleted_at IS NULL AND (NOT EXISTS(SELECT 1 FROM accounts WHERE id=p.account_id) OR NOT EXISTS(SELECT 1 FROM users WHERE id=p.owner_id)) ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED) UPDATE email_providers p SET enabled=false,deleted_at=clock_timestamp(),credential_key_id=NULL,credential_ciphertext=NULL,revision=revision+1 FROM selected s WHERE p.id=s.id`,
			`WITH selected AS(SELECT r.id FROM email_runs r WHERE status IN ('queued','running') AND NOT EXISTS(SELECT 1 FROM email_providers p WHERE p.id=r.provider_id AND p.deleted_at IS NULL AND p.enabled AND p.revision=r.provider_revision) ORDER BY r.id LIMIT 100 FOR UPDATE SKIP LOCKED) UPDATE email_runs r SET status='cancelled',failure_code='provider_unavailable',attempt_token=NULL,attempt_deadline=NULL,finished_at=clock_timestamp() FROM selected s WHERE r.id=s.id`,
			`DELETE FROM email_parts WHERE id IN(SELECT p.id FROM email_parts p WHERE NOT EXISTS(SELECT 1 FROM accounts WHERE id=p.account_id) ORDER BY p.id LIMIT 100)`,
			`DELETE FROM email_messages WHERE id IN(SELECT m.id FROM email_messages m WHERE NOT EXISTS(SELECT 1 FROM accounts WHERE id=m.account_id) AND NOT EXISTS(SELECT 1 FROM email_parts p WHERE p.message_id=m.id) ORDER BY m.id LIMIT 100)`,
			`DELETE FROM email_executions WHERE run_id IN(SELECT e.run_id FROM email_executions e JOIN email_runs r ON r.id=e.run_id WHERE e.closed_at IS NOT NULL AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=r.account_id) ORDER BY e.run_id LIMIT 100)`,
			`DELETE FROM email_outbox WHERE run_id IN(SELECT o.run_id FROM email_outbox o JOIN email_runs r ON r.id=o.run_id WHERE r.status NOT IN ('queued','running') AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=r.account_id) AND NOT EXISTS(SELECT 1 FROM email_executions e WHERE e.run_id=o.run_id) ORDER BY o.run_id LIMIT 100)`,
			`DELETE FROM email_runs WHERE id IN(SELECT r.id FROM email_runs r WHERE r.status NOT IN ('queued','running') AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=r.account_id) AND NOT EXISTS(SELECT 1 FROM email_executions e WHERE e.run_id=r.id) AND NOT EXISTS(SELECT 1 FROM email_outbox o WHERE o.run_id=r.id) AND NOT EXISTS(SELECT 1 FROM email_messages m WHERE m.run_id=r.id) ORDER BY r.id LIMIT 100)`,
			`DELETE FROM email_mailboxes WHERE (provider_id,source_generation) IN(SELECT b.provider_id,b.source_generation FROM email_mailboxes b JOIN email_providers p ON p.id=b.provider_id WHERE NOT EXISTS(SELECT 1 FROM accounts WHERE id=p.account_id) AND NOT EXISTS(SELECT 1 FROM email_messages m WHERE m.provider_id=b.provider_id AND m.source_generation=b.source_generation) ORDER BY b.provider_id,b.source_generation LIMIT 100)`,
			`DELETE FROM email_providers WHERE id IN(SELECT p.id FROM email_providers p WHERE NOT EXISTS(SELECT 1 FROM accounts WHERE id=p.account_id) AND NOT EXISTS(SELECT 1 FROM email_mailboxes b WHERE b.provider_id=p.id) AND NOT EXISTS(SELECT 1 FROM email_runs r WHERE r.provider_id=p.id) AND NOT EXISTS(SELECT 1 FROM email_messages m WHERE m.provider_id=p.id) ORDER BY p.id LIMIT 100)`,
			`DELETE FROM email_test_limits WHERE owner_id IN(SELECT l.owner_id FROM email_test_limits l WHERE NOT EXISTS(SELECT 1 FROM users WHERE id=l.owner_id) ORDER BY l.owner_id LIMIT 100)`,
		}
		for _, statement := range statements {
			if _, err := tx.Exec(ctx, statement); err != nil {
				return err
			}
		}
		return nil
	})
}
