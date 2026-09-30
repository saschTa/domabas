package interfaces

import (
	"context"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type EmailMailboxSession interface {
	Info() m.EmailMailbox
	Discover(context.Context, int64, int64, time.Time) (m.EmailDiscovery, error)
	Fetch(context.Context, int64, func(m.EmailMessage) error) (m.EmailMessage, error)
	Close() error
}
type EmailGateway interface {
	Connect(context.Context, m.EmailConnection) (EmailMailboxSession, error)
}
type EmailCredentialVault interface {
	Available() bool
	ActiveID() string
	KeyIDs() []string
	Seal(m.EmailCredentialIdentity, m.EmailCredentials) (string, []byte, error)
	Open(m.EmailCredentialIdentity, string, []byte) (m.EmailCredentials, error)
}
