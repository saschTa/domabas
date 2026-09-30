package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
)

const chatProviderResponseLimit = 256 << 10

var errChatModelMissing = errors.New("chat model missing")

type ChatProviderRemoteDataSource struct {
	ollama string
	client *http.Client
	logger *slog.Logger
}

func NewChatProviderRemoteDataSource(ollamaOrigin string, loggers ...*slog.Logger) (*ChatProviderRemoteDataSource, error) {
	parsed, err := url.Parse(ollamaOrigin)
	if err != nil || !validProviderURL(parsed) || (parsed.Path != "" && parsed.Path != "/") {
		return nil, errors.New("chat Ollama URL must be an HTTP(S) origin")
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	var logger *slog.Logger
	if len(loggers) > 0 {
		logger = loggers[0]
	}
	return &ChatProviderRemoteDataSource{
		logger: logger,
		ollama: strings.TrimRight(ollamaOrigin, "/"),
		client: &http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }},
	}, nil
}

func (p *ChatProviderRemoteDataSource) Close() { p.client.CloseIdleConnections() }

func validProviderURL(parsed *url.URL) bool {
	return parsed != nil && (parsed.Scheme == "http" || parsed.Scheme == "https") && parsed.Hostname() != "" && parsed.User == nil && parsed.RawQuery == "" && parsed.Fragment == ""
}

func (p *ChatProviderRemoteDataSource) UsesInternalRuntime(configuration m.ChatConfiguration) bool {
	if configuration.Provider == "ollama" {
		return true
	}
	configured, err := url.Parse(configuration.BaseURL)
	if err != nil || !validProviderURL(configured) {
		return false
	}
	internal, _ := url.Parse(p.ollama)
	return strings.EqualFold(configured.Scheme, internal.Scheme) && strings.EqualFold(configured.Hostname(), internal.Hostname()) && providerPort(configured) == providerPort(internal)
}

func providerPort(parsed *url.URL) string {
	if port := parsed.Port(); port != "" {
		return port
	}
	if parsed.Scheme == "https" {
		return "443"
	}
	return "80"
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
	switch input.Configuration.Provider {
	case "ollama":
		return p.generateOllama(ctx, input)
	case "openai":
		parsed, err := url.Parse(input.Configuration.BaseURL)
		if err != nil || !validProviderURL(parsed) {
			return m.ChatAction{}, m.ChatProcessingError{Code: "configuration_unavailable"}
		}
		return p.generateExternal(ctx, input)
	default:
		return m.ChatAction{}, m.ChatProcessingError{Code: "configuration_unavailable"}
	}
}

func (p *ChatProviderRemoteDataSource) request(ctx context.Context, method, endpoint, key string, input, output any, limit int64) error {
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
	if response.StatusCode == http.StatusNotFound {
		return errors.Join(errChatModelMissing, m.ChatProcessingError{Code: "provider_rejected"})
	}
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

func (p *ChatProviderRemoteDataSource) generateOllama(ctx context.Context, input m.ChatInferenceInput) (action m.ChatAction, resultError error) {
	requested := input.Configuration.ContextLength
	if requested == 0 {
		requested = m.ChatDefaultContextLength
	}
	if requested < m.ChatMinimumContextLength || requested > m.ChatMaximumContextLength {
		return m.ChatAction{}, m.ChatProcessingError{Code: "configuration_unavailable"}
	}
	modelContext, err := p.modelInformation(ctx, input.Configuration.Model)
	if errors.Is(err, errChatModelMissing) {
		var pulled struct {
			Status string `json:"status"`
		}
		err = p.request(ctx, http.MethodPost, p.ollama+"/api/pull", "", map[string]any{"model": input.Configuration.Model, "stream": false}, &pulled, chatProviderResponseLimit)
		if err == nil && pulled.Status != "success" {
			err = m.ChatProcessingError{Code: "provider_unavailable", Retryable: true}
		}
		if err == nil {
			modelContext, err = p.modelInformation(ctx, input.Configuration.Model)
		}
	}
	if err != nil {
		return m.ChatAction{}, err
	}
	transcript := providerTranscriptMapper(input.Messages)
	encoded, err := json.Marshal(transcript)
	if err != nil {
		return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
	}
	var response chatInferenceResponse
	schema := chatActionSchemaMapper(input.AnswerOnly || input.ToolsUsed == m.ChatMaxToolCalls)
	thinking := input.Configuration.ThinkingEnabled
	outputBudget := 2048
	if thinking {
		outputBudget += 4096
	}
	requestPayload := map[string]any{
		"model": input.Configuration.Model, "stream": false, "format": schema,
		"messages":   []ChatProviderMessage{{Role: "user", Content: chatOllamaPromptMapper(input, encoded, schema)}},
		"keep_alive": "5m", "options": map[string]any{"temperature": 0.2, "num_ctx": min(requested, modelContext.MaxContextLength), "num_predict": outputBudget},
	}
	requestPayload["think"] = thinking
	start := time.Now()
	err = p.request(ctx, http.MethodPost, p.ollama+"/api/chat", "", requestPayload, &response, chatProviderResponseLimit)
	defer func() {
		p.logInference(ctx, "chat", input.Configuration.Model, requested, min(requested, modelContext.MaxContextLength), utf8.RuneCount(encoded), outputBudget, thinking, start, response, resultError)
	}()
	if err != nil {
		return m.ChatAction{}, err
	}
	if response.DoneReason == "length" {
		return m.ChatAction{}, m.ChatProcessingError{Code: "output_limit"}
	}
	if !response.Done || response.DoneReason != "stop" {
		return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
	}
	if strings.TrimSpace(response.Message.Content) == "" {
		return m.ChatAction{}, m.ChatProcessingError{Code: "empty_response"}
	}
	var payload ChatProviderActionPayload
	if decodeStrict(response.Message.Content, &payload) != nil || !requiredJSONFields(response.Message.Content, "action", "content", "query", "documentId", "offset") {
		return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
	}
	return validateChatAction(m.ChatAction{Kind: payload.Action, Content: payload.Content, Query: payload.Query, DocumentID: payload.DocumentID, Offset: payload.Offset})
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

func (p *ChatProviderRemoteDataSource) Models(ctx context.Context, limit, offset int) (m.ChatModelPage, error) {
	if limit < 1 || limit > 50 || offset < 0 {
		return m.ChatModelPage{}, m.ChatValidationError{Message: "invalid model pagination"}
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	var catalog ChatOllamaModelCatalog
	if err := p.request(ctx, http.MethodGet, p.ollama+"/api/tags", "", nil, &catalog, 4<<20); err != nil {
		return m.ChatModelPage{}, err
	}
	names := make([]string, 0, len(catalog.Models))
	seen := make(map[string]bool)
	for _, model := range catalog.Models {
		if model.Name != "" && !seen[model.Name] {
			seen[model.Name] = true
			names = append(names, model.Name)
		}
	}
	sort.Strings(names)
	page := m.ChatModelPage{Items: []m.ChatModel{}}
	start := min(offset, len(names))
	end := start + min(limit, len(names)-start)
	for _, name := range names[start:end] {
		page.Items = append(page.Items, m.ChatModel{Name: name})
	}
	if end < len(names) {
		page.NextOffset = &end
	}
	return page, nil
}
