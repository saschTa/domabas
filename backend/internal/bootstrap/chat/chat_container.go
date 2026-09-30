package chat

import (
	"context"
	"log/slog"
	"path/filepath"

	"github.com/domabas/domabas/backend/internal/data/chat/datasources"
	"github.com/domabas/domabas/backend/internal/data/chat/datasources/provider"
	"github.com/domabas/domabas/backend/internal/data/chat/repos"
	chattemporal "github.com/domabas/domabas/backend/internal/data/chat/temporal"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/domain/chat/interfaces"
	"github.com/domabas/domabas/backend/internal/domain/chat/services"
	"github.com/domabas/domabas/backend/internal/domain/chat/workflows"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

type ChatContainer struct {
	service    *services.ChatService
	execution  *services.ChatExecutionService
	provider   *provider.ChatProviderRemoteDataSource
	activities *chattemporal.ChatActivities
}

func NewChatContainer(ctx context.Context, db *postgres.PostgresDatabase, authority interfaces.ChatAuthority, scheduler datasources.ChatResourceScheduler, storageRoot, origin, queue string, logger *slog.Logger) (*ChatContainer, error) {
	if origin == "" {
		origin = "http://127.0.0.1:11435"
	}
	source, err := datasources.NewChatDataSource(ctx, db, filepath.Join(storageRoot, ".secrets", "chat.key"), queue, scheduler)
	if err != nil {
		return nil, err
	}
	remote, err := provider.NewChatProviderRemoteDataSource(origin, logger)
	if err != nil {
		return nil, err
	}
	repository := repos.NewChatRepository(source)
	execution := services.NewChatExecutionService(repository, remote, authority)
	return &ChatContainer{service: services.NewChatService(repository, remote, remote, authority), execution: execution, provider: remote, activities: chattemporal.NewChatActivities(execution)}, nil
}
func (c *ChatContainer) Service() *services.ChatService            { return c.service }
func (c *ChatContainer) Execution() *services.ChatExecutionService { return c.execution }
func (c *ChatContainer) RegisterWorker(registry worker.Registry) {
	registry.RegisterWorkflowWithOptions(workflows.ChatTurnWorkflow, workflow.RegisterOptions{Name: workflows.ChatTurnWorkflowName})
	registry.RegisterActivityWithOptions(c.activities.Run, activity.RegisterOptions{Name: workflows.RunChatTurnActivity})
	registry.RegisterActivityWithOptions(c.activities.RunStep, activity.RegisterOptions{Name: workflows.RunChatStepActivity})
	registry.RegisterActivityWithOptions(c.activities.Fail, activity.RegisterOptions{Name: workflows.FailChatTurnActivity})
}
func (c *ChatContainer) Close() { c.activities.Close(); c.provider.Close() }
