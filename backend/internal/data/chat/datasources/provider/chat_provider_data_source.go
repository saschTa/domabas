package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"

	"github.com/domabas/domabas/backend/internal/data/jobs"
	"io"
	"net/http"
	"net/url"
	"strings"
	"unicode/utf8"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
)

const chatProviderResponseLimit = 256 << 10

type ChatProviderRemoteDataSource struct {
	client *http.Client
}

func NewChatProviderRemoteDataSource() *ChatProviderRemoteDataSource {
	return &ChatProviderRemoteDataSource{client: &http.Client{Transport: http.DefaultTransport.(*http.Transport).Clone(), CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
}

func (p *ChatProviderRemoteDataSource) Close() { p.client.CloseIdleConnections() }

func validProviderURL(parsed *url.URL) bool {
	return parsed != nil && (parsed.Scheme == "http" || parsed.Scheme == "https") && parsed.Hostname() != "" && parsed.User == nil && parsed.RawQuery == "" && parsed.Fragment == ""
}

func (p *ChatProviderRemoteDataSource) Generate(ctx context.Context, input m.ChatInferenceInput) (m.ChatAction, error) {
	if strings.TrimSpace(input.Configuration.Model) == "" || len(input.Configuration.Model) > 200 || len(input.Messages) == 0 {
		return m.ChatAction{}, m.ChatProcessingError{Code: "configuration_unavailable"}
	}
	characters := utf8.RuneCountInString(input.ToolLedger)
	for _, message := range input.Messages {
		characters += utf8.RuneCountInString(message.Content)
		if message.ToolCall != nil {
			characters += utf8.RuneCountInString(message.ToolCall.Arguments)
		}
	}
	if characters > m.ChatMaxContextCharacters || len(input.Messages) > m.ChatMaxContextMessages || input.ToolsUsed < 0 || input.ToolsUsed > m.ChatMaxToolCalls {
		return m.ChatAction{}, m.ChatProcessingError{Code: "resource_limit"}
	}
	ctx, cancel := context.WithTimeout(ctx, m.ChatProviderTimeout)
	defer cancel()
	parsed, err := url.Parse(input.Configuration.BaseURL)
	if input.Configuration.Provider != "openai" || err != nil || !validProviderURL(parsed) {
		return m.ChatAction{}, m.ChatProcessingError{Code: "configuration_unavailable"}
	}
	return p.generateExternal(ctx, input)
}

func (p *ChatProviderRemoteDataSource) request(ctx context.Context, method, endpoint, key string, input, output any, limit int64) error {
	return jobs.RunInference(ctx, endpoint, func(ctx context.Context) error { return p.send(ctx, method, endpoint, key, input, output, limit) })
}

func (p *ChatProviderRemoteDataSource) send(ctx context.Context, method, endpoint, key string, input, output any, limit int64) error {
	var body io.Reader
	if input != nil {
		encoded, err := json.Marshal(input)
		if err != nil {
			return m.ChatProcessingError{Code: "invalid_response"}
		}
		body = bytes.NewReader(encoded)
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return m.ChatProcessingError{Code: "configuration_unavailable"}
	}
	req.Header.Set("Content-Type", "application/json")
	if key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
	}
	response, err := p.client.Do(req)
	if err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return m.ChatProcessingError{Code: "provider_unavailable", Retryable: true}
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return m.ChatProcessingError{Code: "provider_rejected", Retryable: response.StatusCode == http.StatusTooManyRequests || response.StatusCode >= 500}
	}
	encoded, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err != nil {
		return m.ChatProcessingError{Code: "provider_unavailable", Retryable: true}
	}
	if int64(len(encoded)) > limit {
		return m.ChatProcessingError{Code: "resource_limit"}
	}
	if json.Unmarshal(encoded, output) != nil {
		return m.ChatProcessingError{Code: "invalid_response"}
	}
	return nil
}

func (p *ChatProviderRemoteDataSource) generateExternal(ctx context.Context, input m.ChatInferenceInput) (m.ChatAction, error) {
	messages := append([]ChatProviderMessage{{Role: "system", Content: chatInstructionMapper(input)}}, providerTranscriptMapper(input.Messages)...)
	choiceMode := "auto"
	if input.AnswerOnly || input.ToolsUsed == m.ChatMaxToolCalls {
		choiceMode = "none"
	}
	reasoningEffort := "none"
	outputBudget := 2048
	if input.Configuration.ThinkingEnabled {
		reasoningEffort = "medium"
		outputBudget += 4096
	}
	var response ChatCompletionResponse
	err := p.request(ctx, http.MethodPost, strings.TrimRight(input.Configuration.BaseURL, "/")+"/chat/completions", input.APIKey, map[string]any{
		"model": input.Configuration.Model, "stream": false, "messages": messages,
		"tools": chatNativeToolsMapper(), "tool_choice": choiceMode, "parallel_tool_calls": false,
		"temperature": 0.2, "max_tokens": outputBudget, "reasoning_effort": reasoningEffort,
	}, &response, chatProviderResponseLimit)
	if err != nil {
		return m.ChatAction{}, err
	}
	if len(response.Choices) != 1 {
		return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
	}
	choice := response.Choices[0]
	if choice.FinishReason == "length" {
		return m.ChatAction{}, m.ChatProcessingError{Code: "output_limit"}
	}
	if len(choice.Message.ToolCalls) == 0 && choice.FinishReason == "stop" && strings.TrimSpace(choice.Message.Content) == "" {
		return m.ChatAction{}, m.ChatProcessingError{Code: "empty_response"}
	}
	if len(choice.Message.ToolCalls) == 0 && choice.FinishReason == "stop" {
		return validateChatAction(m.ChatAction{Kind: "answer", Content: choice.Message.Content})
	}
	if len(choice.Message.ToolCalls) != 1 || choice.FinishReason != "tool_calls" {
		return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
	}
	call := choice.Message.ToolCalls[0]
	if call.Type != "function" || call.ID == "" || len(call.ID) > 200 {
		return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
	}
	action := m.ChatAction{Kind: call.Function.Name, ToolCallID: call.ID}
	switch call.Function.Name {
	case "list_tools":
		var arguments struct {
			Offset int `json:"offset"`
		}
		if decodeStrict(call.Function.Arguments, &arguments) != nil || !requiredJSONFields(call.Function.Arguments, "offset") {
			return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
		}
		action.Offset = arguments.Offset
	case "search_documents":
		var arguments struct {
			Query  string `json:"query"`
			Offset int    `json:"offset"`
		}
		if decodeStrict(call.Function.Arguments, &arguments) != nil || !requiredJSONFields(call.Function.Arguments, "query", "offset") {
			return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
		}
		action.Query, action.Offset = arguments.Query, arguments.Offset
	case "read_document":
		var arguments struct {
			DocumentID string `json:"documentId"`
			Offset     int    `json:"offset"`
		}
		if decodeStrict(call.Function.Arguments, &arguments) != nil || !requiredJSONFields(call.Function.Arguments, "documentId", "offset") {
			return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
		}
		action.DocumentID, action.Offset = arguments.DocumentID, arguments.Offset
	default:
		return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
	}
	return validateChatAction(action)
}

func decodeStrict(content string, output any) error {
	if !uniqueJSONFields(content) {
		return errors.New("invalid or duplicate JSON fields")
	}
	decoder := json.NewDecoder(strings.NewReader(content))
	decoder.DisallowUnknownFields()
	if !strings.HasPrefix(strings.TrimSpace(content), "{") {
		return errors.New("expected JSON object")
	}
	if err := decoder.Decode(output); err != nil {
		return err
	}
	if decoder.Decode(new(any)) != io.EOF {
		return errors.New("unexpected trailing JSON")
	}
	return nil
}

func uniqueJSONFields(content string) bool {
	decoder := json.NewDecoder(strings.NewReader(content))
	start, err := decoder.Token()
	if err != nil || start != json.Delim('{') {
		return false
	}
	seen := make(map[string]bool)
	for decoder.More() {
		token, err := decoder.Token()
		name, valid := token.(string)
		if err != nil || !valid || seen[name] {
			return false
		}
		seen[name] = true
		if decoder.Decode(new(json.RawMessage)) != nil {
			return false
		}
	}
	end, err := decoder.Token()
	return err == nil && end == json.Delim('}') && decoder.Decode(new(any)) == io.EOF
}

func requiredJSONFields(content string, names ...string) bool {
	var fields map[string]json.RawMessage
	if json.Unmarshal([]byte(content), &fields) != nil {
		return false
	}
	for _, name := range names {
		value, exists := fields[name]
		if !exists || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return false
		}
	}
	return true
}

func validateChatAction(action m.ChatAction) (m.ChatAction, error) {
	valid := action.Offset >= 0
	switch action.Kind {
	case "list_tools":
		valid = valid && action.Offset <= 10000 && action.Content == "" && action.Query == "" && action.DocumentID == ""
	case "answer":
		valid = valid && strings.TrimSpace(action.Content) != "" && utf8.RuneCountInString(action.Content) <= 16000 && action.Query == "" && action.DocumentID == "" && action.Offset == 0
	case "search_documents":
		valid = valid && strings.TrimSpace(action.Query) != "" && utf8.RuneCountInString(action.Query) <= 500 && action.Offset <= 10000 && action.Content == "" && action.DocumentID == ""
	case "read_document":
		id, err := uuid.Parse(action.DocumentID)
		valid = valid && err == nil && id != uuid.Nil && id.String() == action.DocumentID && action.Offset <= 10000000 && action.Content == "" && action.Query == ""
	default:
		valid = false
	}
	if !valid {
		return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
	}
	return action, nil
}
