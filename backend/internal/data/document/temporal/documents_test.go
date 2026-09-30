package temporal_test

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"

	adapter "github.com/domabas/domabas/backend/internal/data/document/temporal"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/testsuite"
	"go.temporal.io/sdk/workflow"
)

const accountID = "e9d6f5eb-151a-4889-b70d-ad7ce0f98e03"

type readerFunc func(context.Context, string, string) (document.Document, error)

func (read readerFunc) Get(ctx context.Context, account, id string) (document.Document, error) {
	return read(ctx, account, id)
}

func TestWorkflowRetryClassificationAndMinimalResult(t *testing.T) {
	const id = "b25f9c51-87c5-48b1-8460-65ea11babc99"
	createdAt := time.Date(2026, 9, 17, 12, 0, 0, 0, time.UTC)
	for _, scenario := range []struct {
		name             string
		id               string
		failures         int32
		err              error
		wantCalls        int32
		wantError        bool
		wantNonRetryable bool
	}{
		{name: "success", id: id, wantCalls: 1},
		{name: "invalid identifier", id: "not-a-uuid", wantError: true, wantNonRetryable: true},
		{name: "missing document", id: id, failures: 10, err: document.ErrNotFound, wantCalls: 1, wantError: true, wantNonRetryable: true},
		{name: "invalid document", id: id, failures: 10, err: document.DocumentValidationError{Message: "invalid"}, wantCalls: 1, wantError: true, wantNonRetryable: true},
		{name: "transient failure", id: id, failures: 2, err: errors.New("temporary database error"), wantCalls: 3},
		{name: "bounded persistent failure", id: id, failures: 10, err: errors.New("temporary database error"), wantCalls: 3, wantError: true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var calls atomic.Int32
			activities := adapter.NewDocumentMetadataActivities(readerFunc(func(_ context.Context, gotAccount, gotID string) (document.Document, error) {
				if gotAccount != accountID {
					t.Errorf("wrong account scope %s", gotAccount)
				}
				attempt := calls.Add(1)
				if attempt <= scenario.failures {
					return document.Document{}, scenario.err
				}
				return document.Document{ID: gotID, Title: "private title", Description: "private description", CreatedAt: createdAt}, nil
			}))
			defer activities.Close()
			var suite testsuite.WorkflowTestSuite
			environment := suite.NewTestWorkflowEnvironment()
			environment.RegisterWorkflowWithOptions(documentworkflows.DocumentMetadataWorkflow, workflow.RegisterOptions{Name: documentworkflows.DocumentMetadataWorkflowName})
			environment.RegisterActivityWithOptions(activities.ReadDocumentMetadata, activity.RegisterOptions{Name: documentworkflows.ReadDocumentMetadataActivity})
			environment.ExecuteWorkflow(documentworkflows.DocumentMetadataWorkflowName, documentworkflows.DocumentMetadataRequest{AccountID: accountID, DocumentID: scenario.id})
			if !environment.IsWorkflowCompleted() {
				t.Fatal("workflow did not complete")
			}
			err := environment.GetWorkflowError()
			if (err != nil) != scenario.wantError {
				t.Fatalf("workflow error %v; want error %v", err, scenario.wantError)
			}
			if calls.Load() != scenario.wantCalls {
				t.Fatalf("got %d repository calls, want %d", calls.Load(), scenario.wantCalls)
			}
			if scenario.wantNonRetryable {
				var applicationError *temporal.ApplicationError
				if !errors.As(err, &applicationError) || !applicationError.NonRetryable() {
					t.Fatalf("error must not retry: %v", err)
				}
			}
			if !scenario.wantError {
				var result documentworkflows.DocumentMetadataResult
				if err := environment.GetWorkflowResult(&result); err != nil {
					t.Fatal(err)
				}
				if result.ID != id || !result.CreatedAt.Equal(createdAt) {
					t.Fatalf("incorrect metadata: %+v", result)
				}
			}
		})
	}
}

func TestCloseCancelsAndDrainsActiveReads(t *testing.T) {
	entered, released := make(chan struct{}), make(chan struct{})
	activities := adapter.NewDocumentMetadataActivities(readerFunc(func(ctx context.Context, _, _ string) (document.Document, error) {
		close(entered)
		<-ctx.Done()
		close(released)
		return document.Document{}, ctx.Err()
	}))
	done := make(chan struct{})
	go func() {
		_, _ = activities.ReadDocumentMetadata(context.Background(), documentworkflows.DocumentMetadataRequest{AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99"})
		close(done)
	}()
	<-entered
	activities.Close()
	select {
	case <-released:
	default:
		t.Fatal("close returned before reader released")
	}
	<-done
	if _, err := activities.ReadDocumentMetadata(context.Background(), documentworkflows.DocumentMetadataRequest{AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99"}); !errors.Is(err, context.Canceled) {
		t.Fatalf("closed adapter accepted new I/O: %v", err)
	}
}

func TestLegacyWorkflowFailsWithoutStorageAndInvalidScope(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	environment := suite.NewTestWorkflowEnvironment()
	environment.RegisterWorkflowWithOptions(documentworkflows.LegacyDocumentMetadataWorkflow, workflow.RegisterOptions{Name: documentworkflows.LegacyDocumentMetadataWorkflowName})
	environment.RegisterActivityWithOptions(adapter.LegacyReadDocumentMetadata, activity.RegisterOptions{Name: documentworkflows.LegacyReadDocumentMetadataActivity})
	environment.ExecuteWorkflow(documentworkflows.LegacyDocumentMetadataWorkflowName, "b25f9c51-87c5-48b1-8460-65ea11babc99")
	var failure *temporal.ApplicationError
	if !errors.As(environment.GetWorkflowError(), &failure) || !failure.NonRetryable() || failure.Type() != "AccountScopeRequired" {
		t.Fatalf("legacy work did not fail closed: %v", environment.GetWorkflowError())
	}
	activities := adapter.NewDocumentMetadataActivities(readerFunc(func(context.Context, string, string) (document.Document, error) {
		t.Fatal("invalid scope reached reader")
		return document.Document{}, nil
	}))
	defer activities.Close()
	for _, account := range []string{"", "invalid", "00000000-0000-0000-0000-000000000000"} {
		_, err := activities.ReadDocumentMetadata(t.Context(), documentworkflows.DocumentMetadataRequest{AccountID: account, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99"})
		if !errors.As(err, &failure) || !failure.NonRetryable() {
			t.Fatalf("invalid scope accepted: %v", err)
		}
	}
}
