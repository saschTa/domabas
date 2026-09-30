package temporal

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/stretchr/testify/mock"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/mocks"
)

type issue12ResolutionService struct {
	outboxStub
	resolve func(context.Context, m.DocumentPendingJob, string, string, bool) error
}

func (s *issue12ResolutionService) ResolveExecution(ctx context.Context, p m.DocumentPendingJob, run, code string, missing bool) error {
	return s.resolve(ctx, p, run, code, missing)
}

func TestIssue12RecoveryDistinguishesReachableNotFoundFromServiceOutage(t *testing.T) {
	for _, scenario := range []struct {
		name    string
		err     error
		resolve bool
	}{{"missing exact known run", serviceerror.NewNotFound("retention expired"), true}, {"server outage", serviceerror.NewUnavailable("server unreachable"), false}, {"transport timeout", context.DeadlineExceeded, false}} {
		t.Run(scenario.name, func(t *testing.T) {
			lease, _ := deliveryFixture()
			pending := m.DocumentPendingJob{Job: lease.Job, WorkflowID: lease.WorkflowID, TaskQueue: lease.TaskQueue, RunID: "retained-run", LeaseToken: "owned-lease", LatestPermitEnd: &lease.PermitEnd}
			calls := 0
			service := &issue12ResolutionService{resolve: func(_ context.Context, got m.DocumentPendingJob, run, code string, missing bool) error {
				calls++
				if got.Job != pending.Job || got.LeaseToken != pending.LeaseToken || run != "" || code != "processing_timeout" || !missing {
					t.Fatalf("missing-history fencing lost reservation identity: %+v %s %s %t", got, run, code, missing)
				}
				return nil
			}}
			remote := mocks.NewClient(t)
			remote.On("DescribeWorkflowExecution", mock.Anything, pending.WorkflowID, pending.RunID).Return(nil, scenario.err).Once()
			dispatcher := NewDocumentIngestionDispatcher(service, remote, "replacement-queue", slog.New(slog.NewTextHandler(io.Discard, nil)))
			err := dispatcher.reconcileJob(t.Context(), pending)
			if scenario.resolve && (err != nil || calls != 1) {
				t.Fatalf("reachable NotFound not handed to SQL horizon guard: %d %v", calls, err)
			}
			if !scenario.resolve && (!errors.Is(err, scenario.err) || calls != 0) {
				t.Fatalf("outage incorrectly released or fenced ownership: %d %v", calls, err)
			}
			remote.AssertNotCalled(t, "ExecuteWorkflow", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func TestIssue12ExpiredStartPermitNeverReachesTemporal(t *testing.T) {
	lease, _ := deliveryFixture()
	lease.PermitEnd = time.Now().Add(-time.Second)
	released := 0
	service := &issue12ResolutionService{outboxStub: outboxStub{release: func(_ context.Context, got m.DocumentOutboxLease, _ time.Time) error {
		released++
		if got.LeaseToken != lease.LeaseToken || got.WorkflowID != lease.WorkflowID {
			t.Fatal("stale permit changed execution identity")
		}
		return nil
	}}}
	remote := mocks.NewClient(t)
	dispatcher := NewDocumentIngestionDispatcher(service, remote, lease.TaskQueue, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := dispatcher.deliver(t.Context(), lease); err != nil || released != 1 {
		t.Fatalf("expired permit was not released: %d %v", released, err)
	}
	remote.AssertNotCalled(t, "ExecuteWorkflow", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestIssue12RetentionFailurePreventsNewStartPermissions(t *testing.T) {
	called := false
	service := &issue12ResolutionService{outboxStub: outboxStub{claim: func(context.Context, int, time.Duration) ([]m.DocumentOutboxLease, error) {
		called = true
		return nil, nil
	}}}
	remote := mocks.NewClient(t)
	retention := errors.New("retention below 24 hours")
	dispatcher := NewDocumentIngestionDispatcher(service, remote, "owned-queue", slog.New(slog.NewTextHandler(io.Discard, nil)), func(context.Context) error { return retention })
	if err := dispatcher.dispatch(t.Context()); !errors.Is(err, retention) || called {
		t.Fatalf("unsafe retention still allocated start permission: called=%t err=%v", called, err)
	}
}
