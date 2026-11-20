package provider

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

type ChatCompletionChoice struct {
	Message      ChatProviderMessage `json:"message"`
	FinishReason string              `json:"finish_reason"`
}

type ChatCompletionResponse struct {
	Choices []ChatCompletionChoice `json:"choices"`
}
