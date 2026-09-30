package interfaces

import (
	"context"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type PaperlessJobsRepository interface {
	Settings(context.Context, d.DocumentActor) (m.PaperlessSettings, error)
	UpdateSettings(context.Context, d.DocumentActor, m.PaperlessSettingsUpdate) (m.PaperlessSettings, error)
	Create(context.Context, d.DocumentActor, string, m.PaperlessConnection) (m.PaperlessRun, error)
	List(context.Context, d.DocumentActor, m.PaperlessPageRequest) (m.PaperlessRunPage, error)
	Outcomes(context.Context, d.DocumentActor, string, m.PaperlessPageRequest) (m.PaperlessOutcomePage, error)
	Get(context.Context, d.DocumentActor, string) (m.PaperlessRun, error)
	Cancel(context.Context, d.DocumentActor, string, m.PaperlessTerminalCommand) (m.PaperlessRun, error)
	Next(context.Context) (*m.PaperlessExecution, error)
	WorkIdentity(context.Context, string) (d.DocumentActor, error)
	RunFacts(context.Context, string) (m.PaperlessRunFacts, error)
	Work(context.Context, string, m.PaperlessWorkCommand) (m.PaperlessWork, error)
	RunActive(context.Context, string) (bool, error)
	ReleaseClaims(context.Context, string, []m.PaperlessRetrieval) error
	PageFacts(context.Context, string) (m.PaperlessPageFacts, error)
	RecordPage(context.Context, string, m.PaperlessPageCommand) error
	RecordOutcome(context.Context, string, m.PaperlessOutcome) error
	Finish(context.Context, string, m.PaperlessTerminalCommand) error
	Closed(context.Context, string) error
}
