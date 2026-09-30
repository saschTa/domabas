package models

import (
	"slices"
	"testing"
)

func TestChatCancellationAndClosureKeepPrivacyFences(t *testing.T) {
	cancel := ChatCancellation()
	if !slices.Equal(cancel.ExpectedStates, []string{"queued", "running"}) || cancel.Status != "cancelled" || !cancel.Cleanup.Deleted || !cancel.Cleanup.ExecutionsClosed {
		t.Fatal(cancel)
	}
	closed := ChatClosure("chat_failed")
	if closed.Status != "failed" || closed.FailureCode != "chat_failed" || closed.Cleanup != cancel.Cleanup {
		t.Fatal(closed)
	}
	if ChatAcquisition(false).ReplayState != "" || ChatAcquisition(true).ReplayState != "completed" || ChatAcquisition(false).Lease != ChatActivityLease {
		t.Fatal("acquisition policy changed")
	}
	if ChatValidExecutionStage("complete") || !ChatValidExecutionStage("generating") {
		t.Fatal("invalid execution stage policy")
	}
}
