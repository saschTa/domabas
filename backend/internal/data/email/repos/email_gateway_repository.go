package repos

import (
	"context"

	"github.com/domabas/domabas/backend/internal/data/email/datasources/imap"
	p "github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type EmailGatewaySource interface {
	Connect(context.Context, m.EmailConnection) (*imap.EmailIMAPSession, error)
}
type EmailGatewayRepository struct{ source EmailGatewaySource }

func NewEmailGatewayRepository(source EmailGatewaySource) *EmailGatewayRepository {
	return &EmailGatewayRepository{source: source}
}
func (g *EmailGatewayRepository) Connect(ctx context.Context, connection m.EmailConnection) (p.EmailMailboxSession, error) {
	return g.source.Connect(ctx, connection)
}
