package models

import "slices"

func ChatCancellation() ChatCancellationCommand {
	return ChatCancellationCommand{ExpectedStates: []string{"queued", "running"}, Status: "cancelled", Stage: "cancelled", Cleanup: ChatPrivacyCleanup{Deleted: true, ExecutionsClosed: true, ReplacementTitle: "Deleted chat"}}
}

func ChatClosure(code string) ChatClosureCommand {
	return ChatClosureCommand{ExpectedStates: []string{"queued", "running"}, Status: "failed", Stage: "failed", FailureCode: code, Cleanup: ChatPrivacyCleanup{Deleted: true, ExecutionsClosed: true, ReplacementTitle: "Deleted chat"}}
}

func ChatAcquisition(replay bool) ChatAcquisitionCommand {
	command := ChatAcquisitionCommand{ExpectedStates: []string{"queued", "running"}, Status: "running", Stage: "preparing", Lease: ChatActivityLease}
	if replay {
		command.ReplayState = "completed"
	}
	return command
}

func ChatValidExecutionStage(stage string) bool {
	return slices.Contains([]string{"preparing", "generating", "searching_documents", "reading_document"}, stage)
}

func ChatSchedulerProviders(endpoint string, internal bool) []string {
	if internal {
		return []string{"ollama"}
	}
	return []string{endpoint}
}
