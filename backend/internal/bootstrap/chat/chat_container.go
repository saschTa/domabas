package chat

import (
	"context"
	"path/filepath"

	"github.com/domabas/domabas/backend/internal/data/chat/datasources"
	"github.com/domabas/domabas/backend/internal/data/chat/datasources/provider"
	"github.com/domabas/domabas/backend/internal/data/chat/repos"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/domain/chat/interfaces"
	"github.com/domabas/domabas/backend/internal/domain/chat/services"
)

type ChatContainer struct {
	service   *services.ChatService
	execution *services.ChatExecutionService
	provider  *provider.ChatProviderRemoteDataSource
}

func NewChatContainer(ctx context.Context, db *postgres.PostgresDatabase, authority interfaces.ChatAuthority, scheduler datasources.ChatResourceScheduler, storageRoot, queue string) (*ChatContainer, error) {
	source, err := datasources.NewChatDataSource(ctx, db, filepath.Join(storageRoot, ".secrets", "chat.key"), queue, scheduler)
	if err != nil {
		return nil, err
	}
	remote := provider.NewChatProviderRemoteDataSource()
	repository := repos.NewChatRepository(source)
	execution := services.NewChatExecutionService(repository, remote, authority)
	return &ChatContainer{service: services.NewChatService(repository, authority), execution: execution, provider: remote}, nil
}
func (c *ChatContainer) Service() *services.ChatService            { return c.service }
func (c *ChatContainer) Execution() *services.ChatExecutionService { return c.execution }
func (c *ChatContainer) Close()                                    { c.provider.Close() }
