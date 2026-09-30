package datasources

import (
	"context"
	"crypto/rand"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func lockChatConfiguration(ctx context.Context, tx pgx.Tx) (m.ChatConfiguration, error) {
	return queryChatConfiguration(ctx, tx, " FOR UPDATE")
}
func readChatConfiguration(ctx context.Context, tx pgx.Tx) (m.ChatConfiguration, error) {
	return queryChatConfiguration(ctx, tx, "")
}
func shareChatConfiguration(ctx context.Context, tx pgx.Tx) (m.ChatConfiguration, error) {
	return queryChatConfiguration(ctx, tx, " FOR SHARE")
}
func queryChatConfiguration(ctx context.Context, tx pgx.Tx, lock string) (m.ChatConfiguration, error) {
	var c m.ChatConfiguration
	err := tx.QueryRow(ctx, `SELECT revision,enabled,provider,model,base_url,COALESCE(credential_id::text,''),internal_runtime,updated_at,context_length,thinking_enabled FROM chat_configuration WHERE singleton`+lock).Scan(&c.Revision, &c.Enabled, &c.Provider, &c.Model, &c.BaseURL, &c.CredentialID, &c.InternalRuntime, &c.UpdatedAt, &c.ContextLength, &c.ThinkingEnabled)
	c.HasAPIKey = c.CredentialID != ""
	return c, err
}
func (s *ChatDataSource) Configuration(ctx context.Context, a m.ChatActor, admin bool) (m.ChatConfiguration, error) {
	var c m.ChatConfiguration
	err := s.readTx(ctx, a, admin, func(tx pgx.Tx) error { var err error; c, err = readChatConfiguration(ctx, tx); return err })
	return c, err
}
func (s *ChatDataSource) UpdateConfiguration(ctx context.Context, a m.ChatActor, plan m.ChatConfigurationPlan) (m.ChatConfiguration, error) {
	u := plan.Configuration
	var c m.ChatConfiguration
	err := s.actorTx(ctx, a, true, func(tx pgx.Tx) error {
		var err error
		c, err = lockChatConfiguration(ctx, tx)
		if err != nil {
			return err
		}
		if c.Revision != plan.ExpectedRevision {
			return m.ErrConflict
		}
		contextLength := u.ContextLength
		credential := u.CredentialID
		if plan.APIKey != nil {
			credential = uuid.NewString()
			nonce := make([]byte, s.vault.NonceSize())
			if _, err := rand.Read(nonce); err != nil {
				return err
			}
			encrypted := s.vault.Seal(nonce, nonce, []byte(*plan.APIKey), []byte(credential))
			if _, err := tx.Exec(ctx, "INSERT INTO chat_credentials(id,encrypted_key) VALUES($1,$2)", credential, encrypted); err != nil {
				return err
			}
		}
		if c.Enabled == u.Enabled && c.Provider == u.Provider && c.Model == u.Model && c.BaseURL == u.BaseURL && c.CredentialID == credential && c.ContextLength == contextLength && c.ThinkingEnabled == u.ThinkingEnabled {
			return nil
		}
		_, err = tx.Exec(ctx, `UPDATE chat_configuration SET revision=revision+1,enabled=$1,provider=$2,model=$3,base_url=$4,credential_id=NULLIF($5,'')::uuid,internal_runtime=$6,context_length=$7,thinking_enabled=$8,updated_at=clock_timestamp() WHERE singleton`, u.Enabled, u.Provider, u.Model, u.BaseURL, credential, u.InternalRuntime, contextLength, u.ThinkingEnabled)
		if err != nil {
			return err
		}
		if c.CredentialID != "" && c.CredentialID != credential {
			if _, err := tx.Exec(ctx, "DELETE FROM chat_credentials c WHERE id=$1 AND NOT EXISTS(SELECT 1 FROM chat_configuration WHERE credential_id=c.id) AND NOT EXISTS(SELECT 1 FROM chat_turns WHERE credential_id=c.id)", c.CredentialID); err != nil {
				return err
			}
		}
		c, err = lockChatConfiguration(ctx, tx)
		return err
	})
	return c, err
}
func (s *ChatDataSource) credential(ctx context.Context, tx pgx.Tx, id string) (string, error) {
	if id == "" {
		return "", nil
	}
	var body []byte
	if err := tx.QueryRow(ctx, "SELECT encrypted_key FROM chat_credentials WHERE id=$1", id).Scan(&body); err != nil {
		return "", err
	}
	if len(body) < s.vault.NonceSize() {
		return "", m.ChatProcessingError{Code: "configuration_unavailable"}
	}
	plain, err := s.vault.Open(nil, body[:s.vault.NonceSize()], body[s.vault.NonceSize():], []byte(id))
	if err != nil {
		return "", m.ChatProcessingError{Code: "configuration_unavailable"}
	}
	defer clear(plain)
	return string(plain), nil
}
