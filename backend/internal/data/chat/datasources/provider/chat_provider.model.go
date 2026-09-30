package provider

type ChatProviderActionPayload struct {
	Action     string `json:"action"`
	Content    string `json:"content"`
	Query      string `json:"query"`
	DocumentID string `json:"documentId"`
	Offset     int    `json:"offset"`
}

type ChatProviderToolFunction struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

type ChatProviderToolCall struct {
	ID       string                   `json:"id"`
	Type     string                   `json:"type"`
	Function ChatProviderToolFunction `json:"function"`
}

type ChatProviderMessage struct {
	Role       string                 `json:"role"`
	Content    string                 `json:"content"`
	ToolCallID string                 `json:"tool_call_id,omitempty"`
	ToolCalls  []ChatProviderToolCall `json:"tool_calls,omitempty"`
}

type ChatOllamaResponse struct {
	Message    ChatProviderMessage `json:"message"`
	Done       bool                `json:"done"`
	DoneReason string              `json:"done_reason"`
}

type ChatCompletionChoice struct {
	Message      ChatProviderMessage `json:"message"`
	FinishReason string              `json:"finish_reason"`
}

type ChatCompletionResponse struct {
	Choices []ChatCompletionChoice `json:"choices"`
}

type ChatOllamaModel struct {
	Name string `json:"name"`
}

type ChatOllamaModelCatalog struct {
	Models []ChatOllamaModel `json:"models"`
}
