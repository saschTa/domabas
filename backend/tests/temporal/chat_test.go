//go:build temporal

package temporal_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/chat/datasources/provider"
	chatadapter "github.com/domabas/domabas/backend/internal/data/chat/temporal"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	w "github.com/domabas/domabas/backend/internal/domain/chat/workflows"
	"github.com/google/uuid"
	enums "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/client"
	sdktemporal "go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

type chatLiveExecutionService struct {
	run  func(context.Context, string) error
	fail func(context.Context, string, string) error
}

func (s *chatLiveExecutionService) Run(ctx context.Context, id string) error { return s.run(ctx, id) }
func (s *chatLiveExecutionService) RunStep(ctx context.Context, id string, _ int) (bool, error) {
	err := s.run(ctx, id)
	return err == nil, err
}
func (s *chatLiveExecutionService) Fail(ctx context.Context, id, code string) error {
	return s.fail(ctx, id, code)
}

func TestRealChatWorkflowWaitsForWorkerAndKeepsProviderContentOutOfHistory(t *testing.T) {
	address, namespace := os.Getenv("TEMPORAL_ADDRESS"), os.Getenv("TEMPORAL_NAMESPACE")
	if address == "" || namespace == "" {
		t.Fatal("TEMPORAL_ADDRESS and TEMPORAL_NAMESPACE are required for real chat Temporal tests")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 90*time.Second)
	defer cancel()
	remote, err := client.DialContext(ctx, client.Options{HostPort: address, Namespace: namespace})
	if err != nil {
		t.Fatal(err)
	}
	queue := "domabas-chat-test-" + uuid.NewString()
	var block atomic.Bool
	started, cancelled := make(chan struct{}), make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		_, _ = io.Copy(io.Discard, request.Body)
		if request.Header.Get("Authorization") != "Bearer PRIVATE-API-KEY-42" {
			t.Error("provider secret missing at provider boundary")
		}
		if block.Load() {
			close(started)
			<-request.Context().Done()
			close(cancelled)
			return
		}
		_, _ = io.WriteString(writer, `{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"SECRET-DOCUMENT-42"}}]}`)
	}))
	providerSource, err := provider.NewChatProviderRemoteDataSource(server.URL)
	if err != nil {
		remote.Close()
		server.Close()
		t.Fatal(err)
	}
	var failureCode atomic.Value
	execution := &chatLiveExecutionService{run: func(call context.Context, _ string) error {
		action, err := providerSource.Generate(call, m.ChatInferenceInput{Configuration: m.ChatConfiguration{Provider: "openai", Model: "fixture", BaseURL: server.URL + "/v1"}, APIKey: "PRIVATE-API-KEY-42", Messages: []m.ChatProviderMessage{{Role: "user", Content: "PRIVATE-QUESTION-42"}}})
		if err == nil && action.Content != "SECRET-DOCUMENT-42" {
			return errors.New("provider answer missing")
		}
		return err
	}, fail: func(_ context.Context, _ string, code string) error { failureCode.Store(code); return nil }}
	activities := chatadapter.NewChatActivities(execution)
	queueWorker := worker.New(remote, queue, worker.Options{MaxConcurrentActivityExecutionSize: 3})
	queueWorker.RegisterWorkflowWithOptions(w.ChatTurnWorkflow, workflow.RegisterOptions{Name: w.ChatTurnWorkflowName})
	queueWorker.RegisterActivityWithOptions(activities.Run, activity.RegisterOptions{Name: w.RunChatTurnActivity})
	queueWorker.RegisterActivityWithOptions(activities.RunStep, activity.RegisterOptions{Name: w.RunChatStepActivity})
	queueWorker.RegisterActivityWithOptions(activities.Fail, activity.RegisterOptions{Name: w.FailChatTurnActivity})
	owned := []client.WorkflowRun{}
	finished := make(map[string]bool)
	workerStarted := false
	t.Cleanup(func() {
		for _, run := range owned {
			if !finished[run.GetID()] {
				cleanup, stop := context.WithTimeout(context.Background(), 5*time.Second)
				_ = remote.TerminateWorkflow(cleanup, run.GetID(), run.GetRunID(), "owned chat test cleanup")
				stop()
			}
		}
		if workerStarted {
			queueWorker.Stop()
		}
		activities.Close()
		providerSource.Close()
		server.Close()
		remote.Close()
	})
	startTurn := func() client.WorkflowRun {
		t.Helper()
		turn := uuid.NewString()
		run, err := remote.ExecuteWorkflow(ctx, client.StartWorkflowOptions{ID: chatadapter.ChatWorkflowID(turn), TaskQueue: queue, WorkflowExecutionTimeout: time.Minute, WorkflowIDReusePolicy: enums.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE}, w.ChatTurnWorkflowName, w.ChatTurnRequest{TurnID: turn, AccountID: uuid.NewString()})
		if err != nil {
			t.Fatal(err)
		}
		owned = append(owned, run)
		return run
	}
	first := startTurn()
	quick, stop := context.WithTimeout(ctx, 200*time.Millisecond)
	err = first.Get(quick, nil)
	stop()
	var deadline *serviceerror.DeadlineExceeded
	if !errors.Is(err, context.DeadlineExceeded) && !errors.As(err, &deadline) {
		t.Fatalf("workflow did not wait for absent worker: %v", err)
	}
	if err := queueWorker.Start(); err != nil {
		t.Fatal(err)
	}
	workerStarted = true
	var result w.ChatTurnResult
	if err := first.Get(ctx, &result); err != nil || result.State != "completed" {
		t.Fatalf("result=%+v err=%v", result, err)
	}
	finished[first.GetID()] = true
	history := remote.GetWorkflowHistory(ctx, first.GetID(), first.GetRunID(), false, enums.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT)
	for history.HasNext() {
		event, err := history.Next()
		if err != nil {
			t.Fatal(err)
		}
		encoded, err := json.Marshal(event)
		if err != nil {
			t.Fatal(err)
		}
		for _, private := range []string{"PRIVATE-API-KEY-42", "PRIVATE-QUESTION-42", "SECRET-DOCUMENT-42"} {
			if strings.Contains(string(encoded), private) {
				t.Fatalf("private provider data in workflow history: %s", private)
			}
		}
	}
	block.Store(true)
	second := startTurn()
	select {
	case <-started:
	case <-ctx.Done():
		t.Fatal("provider never started")
	}
	if err := remote.CancelWorkflow(ctx, second.GetID(), second.GetRunID()); err != nil {
		t.Fatal(err)
	}
	if err := second.Get(ctx, nil); !sdktemporal.IsCanceledError(err) {
		t.Fatalf("workflow not cancelled: %v", err)
	}
	finished[second.GetID()] = true
	select {
	case <-cancelled:
	case <-ctx.Done():
		t.Fatal("provider request not cancelled")
	}
	if failureCode.Load() != "chat_cancelled" {
		t.Fatalf("cancellation outcome=%v", failureCode.Load())
	}
}
