package models

const SchedulerMaximumAdmissionCandidates = 20

type SchedulerAdmissionCandidate struct {
	WorkflowID string
	Providers  []string
}
