package models

import "time"

func PlanDocumentReindexMaintenance(facts DocumentReindexMaintenanceFacts) DocumentReindexMaintenanceCommand {
	command := DocumentReindexMaintenanceCommand{Expected: facts, RecheckAfter: 15 * time.Second}
	counts := map[string]DocumentReindexCounts{}
	for _, v := range facts.Aggregates {
		counts[v.BatchID] = v.Counts
	}
	if enumeration := facts.Enumeration; enumeration != nil {
		command.Cursor = enumeration.Cursor
		command.EnumerationComplete = len(enumeration.Candidates) == 0
		command.EnumerationStatus = "enumerating"
		if command.EnumerationComplete {
			command.EnumerationStatus = "running"
		}
		for _, candidate := range enumeration.Candidates {
			command.Cursor = candidate.Sequence
			if candidate.AlreadyEnrolled {
				continue
			}
			change := DocumentReindexItemChange{BatchID: enumeration.BatchID, AccountID: candidate.AccountID, DocumentID: candidate.ID, Status: "waiting"}
			if !candidate.Original {
				change.Status = "skipped"
				reason := "no_original"
				change.OutcomeCode = &reason
			}
			command.Insertions = append(command.Insertions, change)
			total := counts[change.BatchID]
			total.Discovered++
			adjustReindexCount(&total, change.Status, 1)
			counts[change.BatchID] = total
		}
	}
	for _, facts := range facts.Outcomes {
		change := DocumentReindexItemChange{BatchID: facts.BatchID, DocumentID: facts.DocumentID, Status: facts.ItemStatus, OutcomeCode: facts.FailureCode}
		switch {
		case facts.JobStatus == "succeeded":
			change.Status = "succeeded"
		case facts.JobStatus == "failed":
			change.Status = "failed"
		case facts.Deleted || facts.JobStatus == "cancelled":
			change.Status = "skipped"
			reason := "document_deleted"
			change.OutcomeCode = &reason
		case facts.BatchStatus == "superseded":
			change.Status = "superseded"
		case facts.JobStatus == "superseded" || facts.JobStatus == "":
			change.Status = "waiting"
		}
		change.ClearJob = change.Status == "waiting"
		command.Outcomes = append(command.Outcomes, change)
		total := counts[change.BatchID]
		adjustReindexCount(&total, facts.ItemStatus, -1)
		adjustReindexCount(&total, change.Status, 1)
		counts[change.BatchID] = total
	}
	for _, aggregate := range facts.Aggregates {
		total := counts[aggregate.BatchID]
		complete := aggregate.EnumerationComplete
		status := aggregate.Status
		if facts.Enumeration != nil && facts.Enumeration.BatchID == aggregate.BatchID {
			complete = command.EnumerationComplete
			status = command.EnumerationStatus
		}
		finish := complete && total.Waiting+total.Running == 0
		if status != "superseded" && finish {
			status = "succeeded"
			if total.Failed > 0 {
				status = "completed_with_failures"
			}
		}
		command.Aggregates = append(command.Aggregates, DocumentReindexAggregateChange{BatchID: aggregate.BatchID, Status: status, Counts: total, Finished: finish})
	}
	return command
}

func adjustReindexCount(c *DocumentReindexCounts, status string, change int64) {
	switch status {
	case "waiting":
		c.Waiting += change
	case "running":
		c.Running += change
	case "succeeded":
		c.Succeeded += change
	case "failed":
		c.Failed += change
	case "skipped":
		c.Skipped += change
	case "superseded":
		c.Superseded += change
	}
}

func PlanDocumentReindexSchedule(facts DocumentReindexScheduleFacts) DocumentReindexScheduleCommand {
	command := DocumentReindexScheduleCommand{Expected: facts, Action: "defer", RecheckAfter: 2 * time.Second}
	skip := func(reason string) DocumentReindexScheduleCommand {
		command.Action = "skip"
		command.Status = "skipped"
		command.OutcomeCode = &reason
		return command
	}
	if !facts.Exists {
		return skip("document_deleted")
	}
	if !facts.Original {
		return skip("no_original")
	}
	fingerprint := facts.Configuration.Fingerprint
	matching := facts.Fingerprint == fingerprint && facts.Extraction && (facts.Reason != "manual" || facts.Sequence > facts.Cutoff)
	ready := facts.ProcessingState == "ready" && facts.Fingerprint == fingerprint && facts.MachineFingerprint != nil && *facts.MachineFingerprint == fingerprint
	adoption := facts.Reason == "adoption" && facts.Fingerprint == fingerprint && (facts.MachineFingerprint == nil || *facts.MachineFingerprint == fingerprint)
	if facts.Reason != "manual" && (ready || adoption) {
		return skip("already_current")
	}
	if matching && (facts.JobStatus == "succeeded" || facts.ProcessingState == "queued" || facts.ProcessingState == "processing") {
		command.Action = "reuse"
		command.Status = "running"
		if facts.JobStatus == "succeeded" {
			command.Status = "succeeded"
		}
		return command
	}
	if facts.ProcessingState == "queued" || facts.ProcessingState == "processing" {
		return command
	}
	command.Action = "enqueue"
	command.Status = "running"
	return command
}
