package models

import "time"

type ChatPrivacyCleanup struct {
	Deleted, ExecutionsClosed bool
	ReplacementTitle          string
}

type ChatCancellationCommand struct {
	ExpectedStates []string
	Status, Stage  string
	Cleanup        ChatPrivacyCleanup
}

type ChatClosureCommand struct {
	ExpectedStates             []string
	Status, Stage, FailureCode string
	Cleanup                    ChatPrivacyCleanup
}

type ChatAcquisitionCommand struct {
	ExpectedStates             []string
	Status, Stage, ReplayState string
	Lease                      time.Duration
}
