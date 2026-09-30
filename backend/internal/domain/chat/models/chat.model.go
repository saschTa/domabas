package models

import "time"

type ChatActor struct {
	AccountID, UserID, SessionDigest string
	CredentialRevision               int64
}
type ChatConfiguration struct {
	ThinkingEnabled                        bool
	Revision                               int64
	ContextLength                          int
	Enabled                                bool
	Provider, Model, BaseURL, CredentialID string
	HasAPIKey, InternalRuntime             bool
	UpdatedAt                              time.Time
}
type ChatConfigurationUpdate struct {
	ThinkingEnabled          *bool
	ExpectedRevision         int64
	ContextLength            *int
	Enabled                  bool
	Provider, Model, BaseURL string
	APIKey                   *string
	ClearAPIKey              bool
}
type ChatConversation struct {
	ID, Title, ActiveTurnID string
	CreatedAt, UpdatedAt    time.Time
}
type ChatPageRequest struct {
	Limit  int
	Cursor string
}
type ChatConversationPage struct {
	Items      []ChatConversation
	NextCursor string
}
type ChatMessagePage struct {
	Items      []ChatMessage
	NextCursor string
}
type ChatSource struct{ DocumentID, Title, Excerpt string }
type ChatMessage struct {
	ID, ConversationID, Role, Content, TurnID, Status, Stage, FailureCode, Provider, Model string
	Sequence                                                                               int64
	CreatedAt, UpdatedAt                                                                   time.Time
	Sources                                                                                []ChatSource
}
type ChatSendInput struct{ RequestID, Content string }
type ChatSendResult struct{ UserMessage, AssistantMessage ChatMessage }
type ChatModel struct{ Name string }
type ChatModelContext struct {
	Model            string
	MaxContextLength int
}
type ChatModelPage struct {
	Items      []ChatModel
	NextOffset *int
}
type ChatToolCall struct{ ID, Name, Arguments string }
type ChatProviderMessage struct {
	Role, Content, ToolCallID string
	ToolCall                  *ChatToolCall
}
type ChatInferenceInput struct {
	Configuration ChatConfiguration
	APIKey        string
	Messages      []ChatProviderMessage
	ToolsUsed     int
	ToolLedger    string
	AnswerOnly    bool
}
type ChatAction struct {
	Kind, Content, Query, DocumentID, ToolCallID string
	Offset                                       int
}
type ChatToolResult struct {
	Action     ChatAction
	Content    string
	Sources    []ChatSource
	Outcome    string
	NextOffset *int
}
type ChatWork struct {
	ID, ConversationID, ExecutionToken string
	Actor                              ChatActor
	Configuration                      ChatConfiguration
	APIKey                             string
	Messages                           []ChatMessage
	Tools                              []ChatToolResult
}
type ChatDispatch struct {
	TurnID, AccountID, WorkflowID, TaskQueue, RunID, DeliveryToken string
	FirstStartAt                                                   time.Time
	CancelRequested                                                bool
}

const (
	ChatDefaultContextLength = 32768
	ChatMinimumContextLength = 1024
	ChatMaximumContextLength = 1048576
	ChatMaxMessageCharacters = 8000
	ChatMaxContextCharacters = 48000
	ChatMaxToolCalls         = 30
	ChatMaxNoProgressCalls   = 3
	ChatMaxContextMessages   = 64
	ChatActivityLease        = 180 * time.Second
	ChatProviderTimeout      = 30 * time.Minute
)
