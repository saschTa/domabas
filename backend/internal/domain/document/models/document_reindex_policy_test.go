package models

import "testing"

func TestReindexStartPreservesScopeAndRequestIdentity(t *testing.T) {
	account, user := "account", "user"
	actor := DocumentActor{AccountID: account, UserID: user}
	input := DocumentReindexRequest{RequestID: "request", ConfigurationRevision: 2}
	facts := DocumentReindexStartFacts{ConfigurationRevision: 3, Existing: &DocumentReindexExistingRequest{AccountID: &account, RequesterID: &user, ConfigurationRevision: 2}}
	command, err := PlanDocumentReindexStart(actor, false, input, facts)
	if err != nil || !command.Replay {
		t.Fatalf("replay after config change: %+v %v", command, err)
	}
	if _, err = PlanDocumentReindexStart(actor, true, input, facts); err != ErrNotFound {
		t.Fatalf("foreign scope: %v", err)
	}
	facts.Existing = nil
	if _, err = PlanDocumentReindexStart(actor, false, input, facts); err != ErrConflict {
		t.Fatalf("stale configuration: %v", err)
	}
	facts.ConfigurationRevision = 2
	facts.Active = true
	if _, err = PlanDocumentReindexStart(actor, false, input, facts); err != ErrConflict {
		t.Fatalf("parallel manual batch: %v", err)
	}
}

func TestReindexScheduleRequiresNewExtractionForManualBatches(t *testing.T) {
	fingerprint := "current"
	facts := DocumentReindexScheduleFacts{Reason: "manual", Cutoff: 10, Sequence: 9, Exists: true, Original: true, Extraction: true, ProcessingState: "ready", JobStatus: "succeeded", Fingerprint: fingerprint, MachineFingerprint: &fingerprint, Configuration: DocumentProcessingConfiguration{Fingerprint: fingerprint}}
	if got := PlanDocumentReindexSchedule(facts); got.Action != "enqueue" {
		t.Fatalf("manual requires fresh generation: %+v", got)
	}
	facts.Sequence = 11
	if got := PlanDocumentReindexSchedule(facts); got.Action != "reuse" || got.Status != "succeeded" {
		t.Fatalf("fresh generation: %+v", got)
	}
	facts.Reason = "configuration"
	if got := PlanDocumentReindexSchedule(facts); got.Action != "skip" || got.OutcomeCode == nil || *got.OutcomeCode != "already_current" {
		t.Fatalf("automatic current document: %+v", got)
	}
	facts.Exists = false
	if got := PlanDocumentReindexSchedule(facts); got.OutcomeCode == nil || *got.OutcomeCode != "document_deleted" {
		t.Fatalf("deleted document: %+v", got)
	}
}

func TestReindexMaintenancePreservesTerminalEvidenceAndTotals(t *testing.T) {
	facts := DocumentReindexMaintenanceFacts{
		Outcomes: []DocumentReindexOutcomeFacts{
			{BatchID: "batch", DocumentID: "success", ItemStatus: "running", BatchStatus: "superseded", JobStatus: "succeeded", Deleted: true},
			{BatchID: "batch", DocumentID: "retry", ItemStatus: "running", BatchStatus: "running", JobStatus: "superseded"},
		},
		Aggregates: []DocumentReindexAggregateFacts{{BatchID: "batch", Status: "running", EnumerationComplete: true, Counts: DocumentReindexCounts{Discovered: 2, Running: 2}}},
	}
	command := PlanDocumentReindexMaintenance(facts)
	if command.Outcomes[0].Status != "succeeded" || command.Outcomes[1].Status != "waiting" || !command.Outcomes[1].ClearJob {
		t.Fatalf("outcomes: %+v", command.Outcomes)
	}
	aggregate := command.Aggregates[0]
	if aggregate.Finished || aggregate.Counts.Succeeded != 1 || aggregate.Counts.Waiting != 1 || aggregate.Counts.Running != 0 {
		t.Fatalf("totals: %+v", aggregate)
	}
	facts.Outcomes = facts.Outcomes[:1]
	facts.Aggregates[0].Counts = DocumentReindexCounts{Discovered: 2, Running: 1, Failed: 1}
	command = PlanDocumentReindexMaintenance(facts)
	if got := command.Aggregates[0]; !got.Finished || got.Status != "completed_with_failures" {
		t.Fatalf("completion: %+v", got)
	}
}

func TestReindexEnumerationRetainsExactCountsForExistingItems(t *testing.T) {
	facts := DocumentReindexMaintenanceFacts{
		Enumeration: &DocumentReindexEnumeration{BatchID: "batch", Candidates: []DocumentReindexCandidate{{ID: "old", Sequence: 1, Original: true, AlreadyEnrolled: true}, {ID: "new", Sequence: 2}}},
		Aggregates:  []DocumentReindexAggregateFacts{{BatchID: "batch", Status: "enumerating", Counts: DocumentReindexCounts{Discovered: 1, Succeeded: 1}}},
	}
	command := PlanDocumentReindexMaintenance(facts)
	if command.Cursor != 2 || len(command.Insertions) != 1 || command.Insertions[0].DocumentID != "new" {
		t.Fatalf("enumeration replay: %+v", command)
	}
	counts := command.Aggregates[0].Counts
	if counts.Discovered != 2 || counts.Succeeded != 1 || counts.Skipped != 1 {
		t.Fatalf("duplicate changed counts: %+v", counts)
	}
}
