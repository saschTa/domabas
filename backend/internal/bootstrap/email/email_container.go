package email

import (
	"context"
	"time"

	"github.com/domabas/domabas/backend/internal/data/email/datasources"
	"github.com/domabas/domabas/backend/internal/data/email/datasources/imap"
	"github.com/domabas/domabas/backend/internal/data/email/repos"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	"github.com/domabas/domabas/backend/internal/domain/email/services"
	emailworkflows "github.com/domabas/domabas/backend/internal/domain/email/workflows"

	emailtemporal "github.com/domabas/domabas/backend/internal/data/email/temporal"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

type EmailOptions struct {
	Scheduler                                              datasources.EmailResourceScheduler
	CredentialKeys, ActiveKeyID, CredentialKeyFile, CAFile string
	AllowedHosts                                           []string
}

type EmailContainer struct {
	service    *services.EmailService
	polling    *services.EmailPollingService
	repository *repos.EmailRepository
	activities *emailtemporal.EmailPollActivities
}

func NewEmailContainer(ctx context.Context, database *postgres.PostgresDatabase, authority interfaces.EmailAuthority, importer interfaces.EmailDocumentImporter, client emailtemporal.EmailTemporalClient, options EmailOptions, now func() time.Time) (*EmailContainer, error) {
	vault, err := datasources.CredentialKeyring(ctx, database, options.CredentialKeys, options.ActiveKeyID, options.CredentialKeyFile)
	if err != nil {
		return nil, err
	}
	transport, err := imap.NewEmailIMAPDataSource(options.CAFile, options.AllowedHosts)
	if err != nil {
		return nil, err
	}
	gateway := repos.NewEmailGatewayRepository(transport)
	source := datasources.NewEmailDataSource(database, options.Scheduler)
	repository := repos.NewEmailRepository(source, vault)
	pollingRepository := repos.NewEmailPollingRepository(source, vault)
	polling := services.NewEmailPollingService(pollingRepository, pollingRepository, gateway, importer, now, authority)
	return &EmailContainer{service: services.NewEmailService(repository, gateway, vault.Available(), authority), polling: polling, repository: repository, activities: emailtemporal.NewEmailPollActivities(polling, client)}, nil
}

func (c *EmailContainer) Service() *services.EmailService        { return c.service }
func (c *EmailContainer) Polling() *services.EmailPollingService { return c.polling }
func (c *EmailContainer) Rotation() *services.EmailService       { return c.service }
func (c *EmailContainer) RegisterWorker(registry worker.Registry) {
	registry.RegisterWorkflowWithOptions(emailworkflows.EmailPollWorkflow, workflow.RegisterOptions{Name: emailworkflows.EmailPollWorkflowName})
	registry.RegisterActivityWithOptions(c.activities.Page, activity.RegisterOptions{Name: emailworkflows.EmailPollPageActivityName})
}
func (c *EmailContainer) Close() { c.activities.Close() }
