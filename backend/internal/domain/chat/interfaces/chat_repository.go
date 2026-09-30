package interfaces

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
)

type ChatRepository interface {
	Configuration(context.Context, m.ChatActor, bool) (m.ChatConfiguration, error)
	UpdateConfiguration(context.Context, m.ChatActor, m.ChatConfigurationPlan) (m.ChatConfiguration, error)
	Conversations(context.Context, m.ChatActor, m.ChatPageRequest) (m.ChatConversationPage, error)
	CreateConversation(context.Context, m.ChatActor, string) (m.ChatConversation, error)
	Conversation(context.Context, m.ChatActor, string) (m.ChatConversation, error)
	DeleteConversation(context.Context, m.ChatActor, string, m.ChatCancellationCommand) error
	Messages(context.Context, m.ChatActor, string, m.ChatPageRequest) (m.ChatMessagePage, error)
	SendFacts(context.Context, m.ChatActor, string, m.ChatSendInput) (m.ChatSendFacts, error)
	Send(context.Context, m.ChatActor, string, m.ChatSendCommand) (m.ChatSendResult, error)
	Cancel(context.Context, m.ChatActor, string, string, m.ChatCancellationCommand) (m.ChatMessage, error)
}
type ChatExecutionRepository interface {
	ExecutionAuthority(context.Context, string, m.ChatContextQuery) (m.ChatExecutionAuthority, error)
	Dispatch(context.Context) ([]m.ChatDispatch, error)
	Acknowledge(context.Context, m.ChatDispatch, string) error
	ReleaseDelivery(context.Context, m.ChatDispatch) error
	Closed(context.Context, m.ChatDispatch, m.ChatClosureCommand) error
	Acquire(context.Context, string, string, m.ChatAcquisitionCommand) error
	AcquireStep(context.Context, string, string, m.ChatAcquisitionCommand) (bool, error)
	Renew(context.Context, string, string, m.ChatContextQuery) error
	Release(context.Context, string, string) error
	Work(context.Context, string, string, m.ChatContextQuery) (m.ChatWork, error)
	SetStage(context.Context, string, string, string) error
	ToolFacts(context.Context, string, string) ([]m.ChatToolResult, error)
	ToolEvidence(context.Context, string, string, m.ChatAction) (m.ChatToolEvidence, error)
	SaveTool(context.Context, string, string, int, m.ChatToolResult) (m.ChatToolResult, error)
	Complete(context.Context, string, string, string, m.ChatContextQuery) error
	Fail(context.Context, string, m.ChatClosureCommand) error
}
type ChatProvider interface {
	Generate(context.Context, m.ChatInferenceInput) (m.ChatAction, error)
	Models(context.Context, int, int) (m.ChatModelPage, error)
	UsesInternalRuntime(m.ChatConfiguration) bool
}
type ChatModelContextProvider interface {
	ModelContext(context.Context, string) (m.ChatModelContext, error)
}
