package interfaces

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type EmailRepository interface {
	List(context.Context, m.EmailActor, int, string) (m.EmailProviderPage, error)
	Get(context.Context, m.EmailActor, string) (m.EmailProvider, error)
	Create(context.Context, m.EmailActor, m.EmailProviderInput) (m.EmailProvider, error)
	UpdateFacts(context.Context, m.EmailActor, string) (m.EmailProviderUpdateFacts, error)
	Update(context.Context, m.EmailActor, m.EmailProviderUpdateCommand) (m.EmailProvider, error)
	Delete(context.Context, m.EmailActor, string, int64) error
	TestCredentials(context.Context, m.EmailActor, m.EmailTestConnection) (m.EmailConnection, error)
	BeginTest(context.Context, m.EmailActor, m.EmailTestAdmission) (string, error)
	EndTest(context.Context, m.EmailActor, string) error
	VerifyTest(context.Context, m.EmailActor, m.EmailTestConnection) error
	Runs(context.Context, m.EmailActor, m.EmailRunQuery) (m.EmailRunPage, error)
	Run(context.Context, m.EmailActor, string) (m.EmailRun, error)
	RequestedRun(context.Context, m.EmailActor, string, m.EmailStartRun) (*m.EmailRun, error)
	Start(context.Context, m.EmailActor, string, m.EmailStartCommand) (m.EmailRun, error)
	Rotate(context.Context, int) error
}
