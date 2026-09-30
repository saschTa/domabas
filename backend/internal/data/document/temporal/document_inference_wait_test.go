package temporal

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"github.com/stretchr/testify/mock"
	enums "go.temporal.io/api/enums/v1"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/mocks"
	"go.temporal.io/sdk/testsuite"
	"go.temporal.io/sdk/workflow"
)

func TestInferenceWorkflowKeepsLegacyTimeoutsAndExtendsNewModelStages(t *testing.T) {
	for _, scenario := range []struct {
		unlimited bool
		version   workflow.Version
	}{{false, workflow.DefaultVersion}, {false, 1}, {false, 2}, {true, workflow.DefaultVersion}, {true, 1}, {true, 2}} {
		unlimited := scenario.unlimited
		var suite testsuite.WorkflowTestSuite
		env := suite.NewTestWorkflowEnvironment()
		env.OnGetVersion("document-processing-timeouts", workflow.DefaultVersion, workflow.Version(2)).Return(scenario.version)
		env.OnGetVersion("document-extraction-capacity-wait", workflow.DefaultVersion, workflow.Version(1)).Return(workflow.DefaultVersion)
		for _, stage := range []string{documentworkflows.ExtractDocumentActivity, documentworkflows.InvoiceDocumentActivity, documentworkflows.EnrichDocumentActivity, documentworkflows.EmbedDocumentActivity, documentworkflows.FinalizeDocumentActivity} {
			env.RegisterActivityWithOptions(func(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
				info := activity.GetInfo(ctx)
				want := 4 * time.Minute
				wantSchedule := 15 * time.Minute
				if unlimited {
					wantSchedule = 10 * 365 * 24 * time.Hour
				}
				if unlimited && (stage == documentworkflows.InvoiceDocumentActivity || stage == documentworkflows.EnrichDocumentActivity || stage == documentworkflows.EmbedDocumentActivity) {
					want = 10 * 365 * 24 * time.Hour
				}
				if unlimited && scenario.version == 1 && stage == documentworkflows.ExtractDocumentActivity {
					want = 8 * time.Minute
				}
				if unlimited && scenario.version == 2 && stage == documentworkflows.ExtractDocumentActivity {
					want = 16 * time.Minute
				}
				if info.StartToCloseTimeout != want || info.ScheduleToCloseTimeout != wantSchedule || info.HeartbeatTimeout != 15*time.Second || input.UnlimitedInference != unlimited {
					t.Errorf("%s: invalid activity timeout or mode: %+v", stage, info)
				}
				return nil
			}, activity.RegisterOptions{Name: stage})
		}
		env.ExecuteWorkflow(documentworkflows.DocumentIngestionWorkflow, documentworkflows.DocumentIngestionRequest{UnlimitedInference: unlimited})
		if err := env.GetWorkflowError(); err != nil {
			t.Fatal(err)
		}
	}
}

func TestNewExtractionActivitiesAllowCapacityWaitingWithoutAnOCRDeadline(t *testing.T) {
	for _, split := range []bool{false, true} {
		var suite testsuite.WorkflowTestSuite
		env := suite.NewTestWorkflowEnvironment()
		for _, stage := range []string{documentworkflows.ExtractDocumentActivity, documentworkflows.InvoiceDocumentActivity, documentworkflows.EnrichDocumentActivity, documentworkflows.EmbedDocumentActivity, documentworkflows.FinalizeDocumentActivity} {
			env.RegisterActivityWithOptions(func(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
				if stage == documentworkflows.ExtractDocumentActivity {
					info := activity.GetInfo(ctx)
					if info.StartToCloseTimeout != 10*365*24*time.Hour || info.HeartbeatTimeout != 15*time.Second {
						t.Errorf("extraction cannot wait for capacity: %+v", info)
					}
				}
				return nil
			}, activity.RegisterOptions{Name: stage})
		}
		input := documentworkflows.DocumentIngestionRequest{UnlimitedInference: true}
		if split {
			env.ExecuteWorkflow(documentworkflows.DocumentSearchableWorkflow, input)
		} else {
			env.ExecuteWorkflow(documentworkflows.DocumentIngestionWorkflow, input)
		}
		if err := env.GetWorkflowError(); err != nil {
			t.Fatal(err)
		}
	}
}

func TestUnlimitedDeliveryDoesNotSetWorkflowDeadline(t *testing.T) {
	lease, _ := deliveryFixture()
	lease.UnlimitedInference = true
	remote := mocks.NewClient(t)
	run := mocks.NewWorkflowRun(t)
	run.On("GetID").Return(lease.WorkflowID)
	run.On("GetRunID").Return("test-run")
	remote.On("ExecuteWorkflow", mock.Anything, mock.MatchedBy(func(options client.StartWorkflowOptions) bool {
		return options.WorkflowExecutionTimeout == 0 && options.WorkflowRunTimeout == 0 && options.ID == lease.WorkflowID
	}), documentworkflows.DocumentIngestionWorkflowName, ingestionRequest(lease.Job, true)).Return(run, nil).Once()
	acknowledged := false
	service := &outboxStub{acknowledge: func(context.Context, document.DocumentOutboxLease, string, string) error {
		acknowledged = true
		return nil
	}}
	dispatcher := NewDocumentIngestionDispatcher(service, remote, "test-queue", slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := dispatcher.deliver(t.Context(), lease); err != nil || !acknowledged {
		t.Fatalf("unlimited delivery: %v", err)
	}
}

func TestSupersededUnlimitedInferenceIsCanceledBeforeCapacityRelease(t *testing.T) {
	lease, response := deliveryFixture()
	remote := mocks.NewClient(t)
	remote.On("DescribeWorkflowExecution", mock.Anything, lease.WorkflowID, "test-run").Return(response, nil).Once()
	remote.On("CancelWorkflow", mock.Anything, lease.WorkflowID, "test-run").Return(nil).Once()
	response.WorkflowExecutionInfo.Status = enums.WORKFLOW_EXECUTION_STATUS_RUNNING
	dispatcher := NewDocumentIngestionDispatcher(nil, remote, "test-queue", slog.New(slog.NewTextHandler(io.Discard, nil)))
	err := dispatcher.reconcileJob(t.Context(), document.DocumentPendingJob{Job: lease.Job, WorkflowID: lease.WorkflowID, TaskQueue: "test-queue", RunID: "test-run", State: "superseded", UnlimitedInference: true})
	if err != nil {
		t.Fatal(err)
	}
}
