package provider

import (
	"context"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"log/slog"
	"slices"
	"strings"
	"time"
	"unicode/utf8"
)

type chatInferenceResponse struct {
	Message struct {
		Content  string `json:"content"`
		Thinking string `json:"thinking"`
	} `json:"message"`
	Done               bool   `json:"done"`
	DoneReason         string `json:"done_reason"`
	PromptTokens       int    `json:"prompt_eval_count"`
	OutputTokens       int    `json:"eval_count"`
	LoadDuration       int64  `json:"load_duration"`
	PromptDuration     int64  `json:"prompt_eval_duration"`
	GenerationDuration int64  `json:"eval_duration"`
}

func (r *ChatProviderRemoteDataSource) logInference(ctx context.Context, task, model string, requested, effective, input, limit int, thinking bool, start time.Time, response chatInferenceResponse, err error) {
	if r.logger == nil {
		return
	}
	outcome := "completed"
	switch {
	case err != nil:
		outcome = "request_failed"
	case response.DoneReason == "length":
		outcome = "output_limit"
	case !response.Done || response.DoneReason != "stop":
		outcome = "invalid_finish"
	case strings.TrimSpace(response.Message.Content) == "":
		outcome = "empty_response"
	}
	var failure m.ChatProcessingError
	if errors.As(err, &failure) {
		outcome = failure.Code
	}
	if errors.Is(err, context.Canceled) {
		outcome = "cancelled"
	}
	if errors.Is(err, context.DeadlineExceeded) {
		outcome = "timeout"
	}
	finish := response.DoneReason
	if !slices.Contains([]string{"stop", "length", ""}, finish) {
		finish = "other"
	}
	r.logger.LogAttrs(ctx, slog.LevelInfo, "ai_inference",
		slog.String("task", task), slog.String("model", model), slog.String("outcome", outcome),
		slog.String("finish_reason", finish), slog.Int("requested_context", requested), slog.Int("effective_context", effective),
		slog.Int("input_characters", input), slog.Int("output_limit", limit), slog.Bool("thinking_requested", thinking),
		slog.Int("thinking_characters", utf8.RuneCountInString(response.Message.Thinking)), slog.Int("content_characters", utf8.RuneCountInString(response.Message.Content)),
		slog.Int("prompt_tokens", response.PromptTokens), slog.Int("generated_tokens", response.OutputTokens),
		slog.Duration("elapsed", time.Since(start)), slog.Duration("load", time.Duration(response.LoadDuration)),
		slog.Duration("prompt_evaluation", time.Duration(response.PromptDuration)), slog.Duration("generation", time.Duration(response.GenerationDuration)))
}
