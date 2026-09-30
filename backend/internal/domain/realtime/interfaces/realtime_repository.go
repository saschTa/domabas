package interfaces

import (
	"context"

	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
)

type RealtimeRepository interface {
	Snapshot(context.Context, m.RealtimeSubject, []m.RealtimeSignal) (m.RealtimeSnapshot, error)
}
type RealtimeAuthenticator interface {
	Authenticate(context.Context, string) (i.IdentityPrincipal, error)
}
type RealtimePolicy interface {
	AllowsAuthority(string, bool, []string, string, string) bool
}
