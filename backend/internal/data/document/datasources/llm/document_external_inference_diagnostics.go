package llm

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"slices"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type documentExternalInferenceResponse struct {
	Choices []struct {
		Message struct {
			Content          string `json:"content"`
			ReasoningContent string `json:"reasoning_content"`
		} `json:"message"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
	} `json:"usage"`
}

type documentInferenceRequestFailure struct {
	cause      error
	statusCode int
	kind       string
	reason     string
}

func (e documentInferenceRequestFailure) Error() string { return e.cause.Error() }
func (e documentInferenceRequestFailure) Unwrap() error { return e.cause }

func documentProviderTransportReason(err error) string {
	var dns *net.DNSError
	var network net.Error
	switch {
	case errors.As(err, &dns):
		return "dns"
	case errors.As(err, &network) && network.Timeout():
		return "timeout"
	case errors.Is(err, syscall.ECONNREFUSED):
		return "connection_refused"
	case errors.Is(err, syscall.ECONNRESET):
		return "connection_reset"
	case errors.Is(err, io.EOF), errors.Is(err, io.ErrUnexpectedEOF):
		return "connection_closed"
	default:
		return "network_error"
	}
}

func documentProviderRejectionReason(body []byte) string {
	var payload struct {
		Error json.RawMessage `json:"error"`
	}
	if json.Unmarshal(body, &payload) != nil {
		return "unclassified"
	}
	var message string
	if json.Unmarshal(payload.Error, &message) != nil {
		var detail struct {
			Message string `json:"message"`
		}
		if json.Unmarshal(payload.Error, &detail) != nil {
			return "unclassified"
		}
		message = detail.Message
	}
	message = strings.ToLower(message)
	switch {
	case strings.Contains(message, "response_format") && strings.Contains(message, "json_schema"):
		return "response_format_requires_json_schema"
	case strings.Contains(message, "context") && (strings.Contains(message, "exceed") || strings.Contains(message, "length") || strings.Contains(message, "limit")):
		return "context_limit"
	case strings.Contains(message, "schema"):
		return "schema_rejected"
	default:
		return "unclassified"
	}
}

func (r *DocumentPropertyRemoteDataSource) logExternalInference(ctx context.Context, task, model, format string, input, limit int, start time.Time, response documentExternalInferenceResponse, err error) {
	if r.logger == nil {
		return
	}
	outcome := "completed"
	if err != nil {
		outcome = "request_failed"
	}
	var failure m.DocumentProcessingError
	if errors.As(err, &failure) {
		outcome = failure.Code
	}
	if errors.Is(err, m.ErrOverloaded) {
		outcome = "overloaded"
	}
	if errors.Is(err, context.Canceled) {
		outcome = "cancelled"
	}
	if errors.Is(err, context.DeadlineExceeded) {
		outcome = "timeout"
	}
	finish, content, reasoning := "", 0, 0
	if len(response.Choices) == 1 {
		finish = response.Choices[0].FinishReason
		content = utf8.RuneCountInString(response.Choices[0].Message.Content)
		reasoning = utf8.RuneCountInString(response.Choices[0].Message.ReasoningContent)
	}
	if !slices.Contains([]string{"stop", "length", "content_filter", "tool_calls", ""}, finish) {
		finish = "other"
	}
	attributes := []slog.Attr{
		slog.String("provider", "openai"), slog.String("task", task), slog.String("model", model),
		slog.String("response_format", format), slog.String("outcome", outcome), slog.String("finish_reason", finish),
		slog.Int("input_characters", input), slog.Int("output_limit", limit), slog.Int("content_characters", content),
		slog.Int("reasoning_characters", reasoning), slog.Int("prompt_tokens", response.Usage.PromptTokens),
		slog.Int("generated_tokens", response.Usage.CompletionTokens), slog.Duration("elapsed", time.Since(start)),
	}
	var requestFailure documentInferenceRequestFailure
	if errors.As(err, &requestFailure) {
		attributes = append(attributes, slog.Int("http_status", requestFailure.statusCode), slog.String("error_kind", requestFailure.kind), slog.String("provider_error_reason", requestFailure.reason))
	} else {
		attributes = append(attributes, slog.Int("http_status", 200))
	}
	level := slog.LevelInfo
	if err != nil {
		level = slog.LevelWarn
	}
	r.logger.LogAttrs(ctx, level, "ai_inference", attributes...)
}
