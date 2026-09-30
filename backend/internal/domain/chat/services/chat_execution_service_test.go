package services

import (
	"context"
	"errors"
	"fmt"
	p "github.com/domabas/domabas/backend/internal/domain/chat/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
	"unicode/utf8"
)

type chatExecutionFixture struct {
	p.ChatExecutionRepository
	mu            sync.Mutex
	work          m.ChatWork
	stages        chan string
	complete      string
	released      bool
	toolOutcome   string
	toolError     error
	completeError error
	backlog       atomic.Bool
	backlogReads  atomic.Int32
}

func (f *chatExecutionFixture) IngestionPending(context.Context) (bool, error) {
	f.backlogReads.Add(1)
	return f.backlog.Load(), nil
}

func (f *chatExecutionFixture) Acquire(context.Context, string, string, m.ChatAcquisitionCommand) error {
	return nil
}
func (f *chatExecutionFixture) AcquireStep(context.Context, string, string, m.ChatAcquisitionCommand) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.complete != "", nil
}
func (f *chatExecutionFixture) Renew(context.Context, string, string, m.ChatContextQuery) error {
	return nil
}
func (f *chatExecutionFixture) Release(context.Context, string, string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.released = true
	return nil
}
func (f *chatExecutionFixture) Work(context.Context, string, string, m.ChatContextQuery) (m.ChatWork, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.work, nil
}
func (f *chatExecutionFixture) SetStage(_ context.Context, _ string, _ string, stage string) error {
	if f.stages != nil {
		f.stages <- stage
	}
	return nil
}
func (f *chatExecutionFixture) Complete(_ context.Context, _ string, _ string, content string, _ m.ChatContextQuery) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.complete = content
	return f.completeError
}
func (f *chatExecutionFixture) ToolFacts(context.Context, string, string) ([]m.ChatToolResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]m.ChatToolResult(nil), f.work.Tools...), nil
}
func (f *chatExecutionFixture) ToolEvidence(context.Context, string, string, m.ChatAction) (m.ChatToolEvidence, error) {
	return m.ChatToolEvidence{Content: `{"items":[]}`, Available: true}, nil
}
func (f *chatExecutionFixture) SaveTool(_ context.Context, _ string, _ string, _ int, result m.ChatToolResult) (m.ChatToolResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	result.Outcome = f.toolOutcome
	if result.Outcome == "" {
		result.Outcome = "progress"
	}
	f.work.Tools = append(f.work.Tools, result)
	return result, f.toolError
}

type chatProviderFixture struct {
	p.ChatProvider
	internal bool
	generate func(context.Context, m.ChatInferenceInput) (m.ChatAction, error)
}

func (f *chatProviderFixture) Generate(ctx context.Context, input m.ChatInferenceInput) (m.ChatAction, error) {
	return f.generate(ctx, input)
}
func (f *chatProviderFixture) UsesInternalRuntime(m.ChatConfiguration) bool { return f.internal }

func chatFixtureWork() m.ChatWork {
	return m.ChatWork{Messages: []m.ChatMessage{{Role: "user", Content: "Find my invoice"}}}
}
func TestChatExecutionToolsResumeWithExternalProvider(t *testing.T) {
	repo := &chatExecutionFixture{work: chatFixtureWork()}
	calls := 0
	provider := &chatProviderFixture{generate: func(_ context.Context, input m.ChatInferenceInput) (m.ChatAction, error) {
		calls++
		if calls == 1 {
			return m.ChatAction{Kind: "search_documents", Query: "invoice", ToolCallID: "one"}, nil
		}
		if len(input.Messages) != 3 || input.Messages[1].ToolCall.ID != "one" || input.Messages[2].ToolCallID != "one" {
			t.Fatal("tool protocol not resumed", input.Messages)
		}
		return m.ChatAction{Kind: "answer", Content: "No invoice found."}, nil
	}}
	service := NewChatExecutionService(repo, provider, chatAllowAuthority{})
	if err := service.Run(t.Context(), "turn"); err != nil {
		t.Fatal(err)
	}
	if repo.complete != "No invoice found." || !repo.released {
		t.Fatal(repo.complete, repo.released)
	}
}
func TestChatAdmittedInferenceDoesNotWaitForIngestion(t *testing.T) {
	for _, internal := range []bool{true, false} {
		t.Run(fmt.Sprint(internal), func(t *testing.T) {
			t.Parallel()
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()
			repo := &chatExecutionFixture{work: chatFixtureWork(), stages: make(chan string, 20)}
			started := make(chan struct{})
			finish := make(chan struct{})
			var calls atomic.Int64
			provider := &chatProviderFixture{internal: internal, generate: func(ctx context.Context, _ m.ChatInferenceInput) (m.ChatAction, error) {
				if calls.Add(1) == 1 {
					close(started)
				}
				select {
				case <-ctx.Done():
					return m.ChatAction{}, ctx.Err()
				case <-finish:
					return m.ChatAction{Kind: "answer", Content: "Admitted answer"}, nil
				}
			}}
			service := NewChatExecutionService(repo, provider, chatAllowAuthority{})
			done := make(chan error, 1)
			go func() { _, err := service.RunStep(ctx, "turn", 0); done <- err }()
			select {
			case <-started:
			case <-ctx.Done():
				t.Fatal(ctx.Err())
			}
			repo.backlog.Store(true)
			select {
			case err := <-done:
				t.Fatalf("admitted inference ended before provider completion: %v", err)
			case <-time.After(1100 * time.Millisecond):
			}
			close(finish)
			if err := <-done; err != nil {
				t.Fatal(err)
			}
			if calls.Load() != 1 || repo.complete != "Admitted answer" || !repo.released || repo.backlogReads.Load() != 0 {
				t.Fatal(calls.Load(), repo.complete, repo.released)
			}
			close(repo.stages)
			for stage := range repo.stages {
				if stage == "waiting_for_ingestion" {
					t.Fatal("admitted turn waited for ingestion")
				}
			}
		})
	}
}
func TestChatCancellationJoinsInferenceBeforeRelease(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	repo := &chatExecutionFixture{work: chatFixtureWork()}
	started := make(chan struct{})
	var active atomic.Bool
	provider := &chatProviderFixture{generate: func(ctx context.Context, _ m.ChatInferenceInput) (m.ChatAction, error) {
		active.Store(true)
		close(started)
		<-ctx.Done()
		active.Store(false)
		return m.ChatAction{}, ctx.Err()
	}}
	service := NewChatExecutionService(repo, provider, chatAllowAuthority{})
	done := make(chan error, 1)
	go func() { _, err := service.RunStep(ctx, "turn", 0); done <- err }()
	<-started
	cancel()
	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if active.Load() || !repo.released {
		t.Fatal("activity released before inference drained")
	}
}

func TestChatStepRecoversCommittedToolWithoutUsingNextRoundsBudget(t *testing.T) {
	repo := &chatExecutionFixture{work: chatFixtureWork(), toolError: errors.New("lost tool commit acknowledgment")}
	calls := 0
	provider := &chatProviderFixture{generate: func(_ context.Context, input m.ChatInferenceInput) (m.ChatAction, error) {
		calls++
		if calls == 1 {
			return m.ChatAction{Kind: "search_documents", Query: "invoice", ToolCallID: "one"}, nil
		}
		if input.ToolsUsed != 1 || input.Messages[len(input.Messages)-1].Role != "tool" {
			t.Fatal("committed tool context lost", input)
		}
		return m.ChatAction{Kind: "answer", Content: "Recovered answer"}, nil
	}}
	service := NewChatExecutionService(repo, provider, chatAllowAuthority{})
	if _, err := service.RunStep(t.Context(), "turn", 0); err == nil {
		t.Fatal("lost acknowledgment did not fail first attempt")
	}
	repo.toolError = nil
	if completed, err := service.RunStep(t.Context(), "turn", 0); err != nil || completed || calls != 1 || len(repo.work.Tools) != 1 {
		t.Fatal("retry executed the next provider round", completed, err, calls, len(repo.work.Tools))
	}
	if completed, err := service.RunStep(t.Context(), "turn", 1); err != nil || !completed || calls != 2 || repo.complete != "Recovered answer" {
		t.Fatal("next round did not resume committed context", completed, err, calls, repo.complete)
	}
}

func TestChatStepRecoversCommittedAnswerWithoutProviderReplay(t *testing.T) {
	repo := &chatExecutionFixture{work: chatFixtureWork(), completeError: errors.New("lost answer commit acknowledgment")}
	calls := 0
	provider := &chatProviderFixture{generate: func(context.Context, m.ChatInferenceInput) (m.ChatAction, error) {
		calls++
		return m.ChatAction{Kind: "answer", Content: "Committed answer"}, nil
	}}
	service := NewChatExecutionService(repo, provider, chatAllowAuthority{})
	if _, err := service.RunStep(t.Context(), "turn", 0); err == nil {
		t.Fatal("lost acknowledgment did not fail first attempt")
	}
	if completed, err := service.RunStep(t.Context(), "turn", 0); err != nil || !completed || calls != 1 || repo.complete != "Committed answer" {
		t.Fatal("committed answer was regenerated", completed, err, calls, repo.complete)
	}
}

func TestChatStepRejectsSkippedRoundWithoutInference(t *testing.T) {
	repo := &chatExecutionFixture{work: chatFixtureWork()}
	provider := &chatProviderFixture{generate: func(context.Context, m.ChatInferenceInput) (m.ChatAction, error) {
		t.Fatal("invalid checkpoint reached provider")
		return m.ChatAction{}, nil
	}}
	service := NewChatExecutionService(repo, provider, chatAllowAuthority{})
	for _, ordinal := range []int{-1, 1, m.ChatMaxToolCalls + 1} {
		if _, err := service.RunStep(t.Context(), "turn", ordinal); err == nil {
			t.Fatal("invalid ordinal accepted", ordinal)
		}
	}
}

func TestChatProviderDeadlineAllowsAdmittedQueueWait(t *testing.T) {
	repo := &chatExecutionFixture{work: chatFixtureWork()}
	provider := &chatProviderFixture{generate: func(ctx context.Context, _ m.ChatInferenceInput) (m.ChatAction, error) {
		deadline, ok := ctx.Deadline()
		remaining := time.Until(deadline)
		if !ok || remaining < 29*time.Minute || remaining > 30*time.Minute {
			t.Errorf("inference deadline does not allow model queue wait: %v", remaining)
		}
		return m.ChatAction{Kind: "answer", Content: "Done"}, nil
	}}
	if _, err := NewChatExecutionService(repo, provider, chatAllowAuthority{}).RunStep(t.Context(), "turn", 0); err != nil {
		t.Fatal(err)
	}
}
func TestChatContextBoundKeepsNativeToolPairsAndLatestPrompt(t *testing.T) {
	work := chatFixtureWork()
	for i := 0; i < 20; i++ {
		work.Messages = append(work.Messages, m.ChatMessage{Role: "user", Content: strings.Repeat("ü", 8000)})
	}
	work.Messages[len(work.Messages)-1].Content = "latest"
	for i := 0; i < m.ChatMaxToolCalls; i++ {
		work.Tools = append(work.Tools, m.ChatToolResult{Action: m.ChatAction{Kind: "read_document", DocumentID: "12345678-1234-4234-8234-123456789012", ToolCallID: "call"}, Content: strings.Repeat("文", 8000)})
	}
	input, err := chatInferenceMapper(work)
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	latest := false
	for i, message := range input.Messages {
		count += utf8.RuneCountInString(message.Content)
		if message.Content == "latest" {
			latest = true
		}
		if message.Role == "tool" && (i == 0 || input.Messages[i-1].ToolCall == nil || input.Messages[i-1].ToolCall.ID != message.ToolCallID) {
			t.Fatal("orphaned tool result")
		}
	}
	if count > m.ChatMaxContextCharacters || !latest {
		t.Fatal(count, latest)
	}
}

func TestChatThirtyToolCallsAndFinalAnswerIncludingRecovery(t *testing.T) {
	for _, recovered := range []int{0, 29, 30} {
		for _, answer := range []bool{true, false} {
			t.Run(fmt.Sprintf("recovered_%d_answer_%v", recovered, answer), func(t *testing.T) {
				work := chatFixtureWork()
				for i := 0; i < recovered; i++ {
					work.Tools = append(work.Tools, m.ChatToolResult{Action: m.ChatAction{Kind: "read_document", DocumentID: "12345678-1234-4234-8234-123456789012", Offset: i * 8000}, Content: `{"text":"evidence"}`, Outcome: "progress"})
				}
				repo := &chatExecutionFixture{work: work}
				calls := 0
				provider := &chatProviderFixture{generate: func(_ context.Context, input m.ChatInferenceInput) (m.ChatAction, error) {
					calls++
					if input.ToolsUsed != recovered+calls-1 {
						t.Fatalf("budget reset: %d", input.ToolsUsed)
					}
					if input.ToolsUsed == m.ChatMaxToolCalls && answer {
						return m.ChatAction{Kind: "answer", Content: "Final evidence answer"}, nil
					}
					return m.ChatAction{Kind: "read_document", DocumentID: "12345678-1234-4234-8234-123456789012", Offset: input.ToolsUsed * 8000}, nil
				}}
				err := NewChatExecutionService(repo, provider, chatAllowAuthority{}).Run(t.Context(), "turn")
				if len(repo.work.Tools) != 30 || calls != 31-recovered {
					t.Fatal(len(repo.work.Tools), calls)
				}
				if answer {
					if err != nil || repo.complete == "" {
						t.Fatal(err, repo.complete)
					}
				} else {
					if err != nil || repo.complete != chatRetrievalFallback {
						t.Fatal("provider noncompliance did not complete safely", err, repo.complete)
					}
				}
			})
		}
	}
}

func TestChatContextThirtySmallToolsKeepsQuestionAndCallLedger(t *testing.T) {
	work := chatFixtureWork()
	for i := 0; i < 20; i++ {
		work.Messages = append(work.Messages, m.ChatMessage{Role: "user", Content: "old"})
	}
	work.Messages = append(work.Messages, m.ChatMessage{Role: "user", Content: strings.Repeat("文", 8000)})
	for i := 0; i < 30; i++ {
		work.Tools = append(work.Tools, m.ChatToolResult{Action: m.ChatAction{Kind: "list_tools", Offset: i}, Content: `{"items":[]}`})
	}
	input, err := chatInferenceMapper(work)
	if err != nil {
		t.Fatal(err)
	}
	if len(input.Messages) > m.ChatMaxContextMessages || input.ToolsUsed != 30 || !strings.Contains(input.ToolLedger, `30: list_tools {"offset":29}`) {
		t.Fatal(input)
	}
	latest := false
	for i, message := range input.Messages {
		if message.Content == work.Messages[len(work.Messages)-1].Content {
			latest = true
		}
		if message.Role == "tool" && (i == 0 || input.Messages[i-1].ToolCall == nil || input.Messages[i-1].ToolCall.ID != message.ToolCallID) {
			t.Fatal("orphaned tool result")
		}
	}
	if !latest {
		t.Fatal("latest user prompt lost")
	}
}

func TestChatExecutionStopsNoProgressAcrossRecovery(t *testing.T) {
	for _, recovered := range []int{0, 2, 3} {
		for _, final := range []string{"answer", "tool", "malformed", "unavailable"} {
			t.Run(fmt.Sprintf("recovered_%d_%s", recovered, final), func(t *testing.T) {
				work := chatFixtureWork()
				for i := 0; i < recovered; i++ {
					work.Tools = append(work.Tools, m.ChatToolResult{Action: m.ChatAction{Kind: "search_documents", Query: "missing"}, Content: `{"items":[]}`, Outcome: "empty_result"})
				}
				repo := &chatExecutionFixture{work: work, toolOutcome: "empty_result"}
				calls := 0
				provider := &chatProviderFixture{generate: func(_ context.Context, input m.ChatInferenceInput) (m.ChatAction, error) {
					calls++
					if input.ToolsUsed == 3 {
						if !input.AnswerOnly {
							t.Fatal("recovered no-progress streak did not disable tools")
						}
						switch final {
						case "answer":
							return m.ChatAction{Kind: "answer", Content: "I could not find that document."}, nil
						case "malformed":
							return m.ChatAction{}, m.ChatProcessingError{Code: "invalid_response"}
						case "unavailable":
							return m.ChatAction{}, m.ChatProcessingError{Code: "provider_unavailable", Retryable: true}
						}
					}
					return m.ChatAction{Kind: "search_documents", Query: "missing"}, nil
				}}
				err := NewChatExecutionService(repo, provider, chatAllowAuthority{}).Run(t.Context(), "turn")
				if len(repo.work.Tools) != 3 || calls != 4-recovered {
					t.Fatal("unbounded no-progress loop", len(repo.work.Tools), calls)
				}
				if final == "unavailable" {
					var failure m.ChatProcessingError
					if !errors.As(err, &failure) || failure.Code != "provider_unavailable" || repo.complete != "" {
						t.Fatal("provider outage was masked", err, repo.complete)
					}
				} else if err != nil || repo.complete == "" {
					t.Fatal("no final answer", err)
				}
			})
		}
	}
}
