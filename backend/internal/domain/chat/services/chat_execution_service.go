package services

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	p "github.com/domabas/domabas/backend/internal/domain/chat/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"time"
)

type ChatExecutionService struct {
	repository p.ChatExecutionRepository
	provider   p.ChatProvider
	authority  p.ChatAuthority
}

func NewChatExecutionService(repository p.ChatExecutionRepository, provider p.ChatProvider, authority p.ChatAuthority) *ChatExecutionService {
	return &ChatExecutionService{repository: repository, provider: provider, authority: authority}
}
func (s *ChatExecutionService) authorize(ctx context.Context, id string, documents bool) error {
	if s.authority == nil {
		return m.ErrForbidden
	}
	facts, err := s.repository.ExecutionAuthority(ctx, id, m.ChatContextSelection())
	if err != nil {
		return err
	}
	a := facts.Actor
	principal, err := s.authority.ResolveBackgroundAuthority(ctx, a.AccountID, a.UserID, a.CredentialRevision)
	if err != nil {
		if errors.Is(err, i.ErrUnauthorized) || errors.Is(err, i.ErrForbidden) || errors.Is(err, i.ErrPasswordChange) {
			return m.ErrForbidden
		}
		return err
	}
	if !principal.HasPermission(i.IdentityPermission("chat:use")) {
		return m.ErrForbidden
	}
	if facts.EvidenceMissing {
		return m.ChatProcessingError{Code: "document_unavailable"}
	}
	if documents || facts.EvidencePresent {
		for _, claim := range []i.IdentityPermission{"documents:read", "documents:search", "documents:ocr:read"} {
			if !principal.HasPermission(claim) {
				return m.ChatProcessingError{Code: "access_revoked"}
			}
		}
	}
	return nil
}
func (s *ChatExecutionService) Dispatch(ctx context.Context) ([]m.ChatDispatch, error) {
	return s.repository.Dispatch(ctx)
}
func (s *ChatExecutionService) Acknowledge(ctx context.Context, d m.ChatDispatch, run string) error {
	return s.repository.Acknowledge(ctx, d, run)
}
func (s *ChatExecutionService) ReleaseDelivery(ctx context.Context, d m.ChatDispatch) error {
	return s.repository.ReleaseDelivery(ctx, d)
}
func (s *ChatExecutionService) Closed(ctx context.Context, d m.ChatDispatch, code string) error {
	return s.repository.Closed(ctx, d, m.ChatClosure(code))
}
func (s *ChatExecutionService) Acquire(ctx context.Context, id, token string) error {
	if err := s.authorize(ctx, id, false); err != nil {
		return err
	}
	return s.repository.Acquire(ctx, id, token, m.ChatAcquisition(false))
}
func (s *ChatExecutionService) AcquireStep(ctx context.Context, id, token string) (bool, error) {
	if err := s.authorize(ctx, id, false); err != nil {
		return false, err
	}
	return s.repository.AcquireStep(ctx, id, token, m.ChatAcquisition(true))
}
func (s *ChatExecutionService) Renew(ctx context.Context, id, token string) error {
	if err := s.authorize(ctx, id, false); err != nil {
		return err
	}
	return s.repository.Renew(ctx, id, token, m.ChatContextSelection())
}
func (s *ChatExecutionService) Release(ctx context.Context, id, token string) error {
	return s.repository.Release(ctx, id, token)
}
func (s *ChatExecutionService) Work(ctx context.Context, id, token string) (m.ChatWork, error) {
	if err := s.authorize(ctx, id, false); err != nil {
		return m.ChatWork{}, err
	}
	return s.repository.Work(ctx, id, token, m.ChatContextSelection())
}
func (s *ChatExecutionService) SetStage(ctx context.Context, id, token, stage string) error {
	if !m.ChatValidExecutionStage(stage) {
		return m.ChatValidationError{Message: "invalid chat execution stage"}
	}
	if err := s.authorize(ctx, id, false); err != nil {
		return err
	}
	return s.repository.SetStage(ctx, id, token, stage)
}
func (s *ChatExecutionService) Tool(ctx context.Context, id, token string, ordinal int, action m.ChatAction) (m.ChatToolResult, error) {
	if err := s.authorize(ctx, id, action.Kind != "list_tools"); err != nil {
		return m.ChatToolResult{}, err
	}
	if err := action.Validate(); err != nil {
		return m.ChatToolResult{}, err
	}
	if ordinal < 0 || ordinal >= m.ChatMaxToolCalls || action.Kind == "answer" {
		return m.ChatToolResult{}, m.ChatProcessingError{Code: "tool_limit"}
	}
	prior, err := s.repository.ToolFacts(ctx, id, token)
	if err != nil {
		return m.ChatToolResult{}, err
	}
	if ordinal < len(prior) {
		if prior[ordinal].Action != action {
			return m.ChatToolResult{}, m.ErrConflict
		}
		return prior[ordinal], nil
	}
	if ordinal != len(prior) {
		return m.ChatToolResult{}, m.ErrConflict
	}
	if m.ChatToolsMustAnswer(prior) {
		return m.ChatToolResult{}, m.ChatProcessingError{Code: "tool_limit"}
	}
	result := m.ChatToolResult{Action: action, Sources: []m.ChatSource{}}
	if rejection := m.ChatToolRejection(action, prior); rejection != "" {
		result.Outcome = rejection
		result.Content = chatToolFeedbackMapper(rejection)
	} else {
		evidence, err := s.repository.ToolEvidence(ctx, id, token, action)
		if err != nil {
			return result, err
		}
		result, err = chatToolEvidenceMapper(action, prior, evidence)
		if err != nil {
			return result, err
		}
	}
	if err := s.authorize(ctx, id, action.Kind != "list_tools"); err != nil {
		return m.ChatToolResult{}, err
	}
	return s.repository.SaveTool(ctx, id, token, ordinal, result)
}
func (s *ChatExecutionService) Complete(ctx context.Context, id, token, content string) error {
	if err := s.authorize(ctx, id, false); err != nil {
		return err
	}
	if err := (m.ChatAction{Kind: "answer", Content: content}).Validate(); err != nil {
		return err
	}
	return s.repository.Complete(ctx, id, token, content, m.ChatContextSelection())
}
func (s *ChatExecutionService) Fail(ctx context.Context, id, code string) error {
	return s.repository.Fail(ctx, id, m.ChatClosure(code))
}
func chatExecutionToken() (string, error) {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	raw[6] = (raw[6] & 15) | 64
	raw[8] = (raw[8] & 63) | 128
	text := hex.EncodeToString(raw[:])
	return text[:8] + "-" + text[8:12] + "-" + text[12:16] + "-" + text[16:20] + "-" + text[20:], nil
}
func (s *ChatExecutionService) Run(ctx context.Context, id string) error {
	token, err := chatExecutionToken()
	if err != nil {
		return err
	}
	if err := s.Acquire(ctx, id, token); err != nil {
		return err
	}
	return s.runOwned(ctx, id, token, func(run context.Context) error {
		return s.runRounds(run, id, token)
	})
}

func (s *ChatExecutionService) RunStep(ctx context.Context, id string, ordinal int) (bool, error) {
	if ordinal < 0 || ordinal > m.ChatMaxToolCalls {
		return false, m.ChatProcessingError{Code: "tool_limit"}
	}
	token, err := chatExecutionToken()
	if err != nil {
		return false, err
	}
	completed, err := s.AcquireStep(ctx, id, token)
	if err != nil || completed {
		return completed, err
	}
	err = s.runOwned(ctx, id, token, func(run context.Context) error {
		work, err := s.Work(run, id, token)
		if err != nil {
			return err
		}
		if len(work.Tools) > ordinal {
			return nil
		}
		if len(work.Tools) < ordinal {
			return m.ChatProcessingError{Code: "chat_failed"}
		}
		completed, err = s.runRound(run, id, token, work)
		return err
	})
	return completed, err
}

func (s *ChatExecutionService) runOwned(ctx context.Context, id, token string, call func(context.Context) error) error {
	run, cancel := context.WithCancel(ctx)
	renewed := make(chan error, 1)
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-run.Done():
				renewed <- nil
				return
			case <-ticker.C:
				probe, stop := context.WithTimeout(run, 5*time.Second)
				err := s.Renew(probe, id, token)
				stop()
				if err != nil {
					cancel()
					renewed <- err
					return
				}
			}
		}
	}()
	defer func() {
		cancel()
		cleanup, stop := context.WithTimeout(context.Background(), 5*time.Second)
		defer stop()
		_ = s.Release(cleanup, id, token)
	}()
	err := call(run)
	cancel()
	renewalErr := <-renewed
	if err == nil {
		return nil
	}
	if renewalErr != nil && ctx.Err() == nil {
		return renewalErr
	}
	return err
}
func (s *ChatExecutionService) runRounds(ctx context.Context, id, token string) error {
	for {
		work, err := s.Work(ctx, id, token)
		if err != nil {
			return err
		}
		completed, err := s.runRound(ctx, id, token, work)
		if err != nil || completed {
			return err
		}
	}
}

func (s *ChatExecutionService) runRound(ctx context.Context, id, token string, work m.ChatWork) (bool, error) {
	if len(work.Tools) > m.ChatMaxToolCalls {
		return false, m.ChatProcessingError{Code: "tool_limit"}
	}
	answerOnly := m.ChatToolsMustAnswer(work.Tools)
	generate := func(call context.Context) (m.ChatAction, error) {
		fresh, err := s.Work(call, id, token)
		if err != nil {
			return m.ChatAction{}, err
		}
		if err := s.SetStage(call, id, token, "generating"); err != nil {
			return m.ChatAction{}, err
		}
		request, err := chatInferenceMapper(fresh)
		if err != nil {
			return m.ChatAction{}, err
		}
		bounded, cancel := context.WithTimeout(call, m.ChatProviderTimeout)
		defer cancel()
		return s.provider.Generate(bounded, request)
	}
	action, err := generate(ctx)
	if err != nil {
		var failure m.ChatProcessingError
		if answerOnly && errors.As(err, &failure) && failure.Code == "invalid_response" {
			return true, s.Complete(ctx, id, token, chatRetrievalFallback)
		}
		return false, err
	}
	if err := action.Validate(); err != nil {
		return false, err
	}
	if action.Kind == "answer" {
		return true, s.Complete(ctx, id, token, action.Content)
	}
	if answerOnly {
		return true, s.Complete(ctx, id, token, chatRetrievalFallback)
	}
	if len(work.Tools) >= m.ChatMaxToolCalls {
		return false, m.ChatProcessingError{Code: "tool_limit"}
	}
	stage := "searching_documents"
	if action.Kind == "list_tools" {
		stage = "preparing"
	}
	if action.Kind == "read_document" {
		stage = "reading_document"
	}
	if err := s.SetStage(ctx, id, token, stage); err != nil {
		return false, err
	}
	_, err = s.Tool(ctx, id, token, len(work.Tools), action)
	return false, err
}

const chatRetrievalFallback = "I could not reliably verify the requested information from your documents. Please try a shorter search term or name a specific document."
