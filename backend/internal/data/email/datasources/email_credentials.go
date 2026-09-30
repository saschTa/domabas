package datasources

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/domabas/domabas/backend/internal/data/email/datasources/credentials"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/jackc/pgx/v5"
)

func CredentialKeyring(ctx context.Context, db *postgres.PostgresDatabase, raw, active, path string) (*credentials.EmailCredentialKeyring, error) {
	if raw != "" || active != "" {
		return credentials.NewEmailCredentialKeyring(raw, active)
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	var ring *credentials.EmailCredentialKeyring
	err := pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='5s'; LOCK TABLE email_providers IN SHARE ROW EXCLUSIVE MODE"); err != nil {
			return err
		}
		var retained bool
		if err := tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM email_providers WHERE credential_ciphertext IS NOT NULL)").Scan(&retained); err != nil {
			return err
		}
		var err error
		ring, err = credentials.LoadFile(path, !retained)
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, "SELECT id,account_id,owner_id,credential_key_id,credential_ciphertext FROM email_providers WHERE credential_ciphertext IS NOT NULL")
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var identity m.EmailCredentialIdentity
			var keyID string
			var ciphertext []byte
			if err := rows.Scan(&identity.ProviderID, &identity.AccountID, &identity.OwnerID, &keyID, &ciphertext); err != nil {
				return err
			}
			if _, err := ring.Open(identity, keyID, ciphertext); err != nil {
				return errors.New("email credential key cannot decrypt retained providers; restore the original key file or explicit keyring")
			}
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("initialize email credentials: %w", err)
	}
	return ring, nil
}
