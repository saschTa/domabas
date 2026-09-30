package models

import "time"

type EmailExecutionFacts struct {
	Status, WorkflowID, TaskQueue, WorkflowRunID string
	PermitEnd, ClosedAt                          *time.Time
	ObservedAt                                   time.Time
}

type EmailExecutionClosureCommand struct {
	Execution                EmailExecution
	Expected                 EmailExecutionFacts
	ObservedRun, FailureCode string
	Apply, FailRun           bool
	EarliestClosure          *time.Time
}

func PlanEmailExecutionClosure(facts EmailExecutionFacts, execution EmailExecution, run, code string, missing bool) (EmailExecutionClosureCommand, error) {
	command := EmailExecutionClosureCommand{Execution: execution, Expected: facts, ObservedRun: run, FailureCode: code}
	if facts.ClosedAt != nil {
		return command, nil
	}
	if facts.WorkflowID != execution.WorkflowID || facts.TaskQueue != execution.TaskQueue || (facts.WorkflowRunID != "" && facts.WorkflowRunID != run && !missing) {
		return command, ErrConflict
	}
	if missing {
		if facts.PermitEnd == nil {
			return command, nil
		}
		earliest := facts.PermitEnd.Add(11 * time.Minute)
		command.EarliestClosure = &earliest
		if facts.ObservedAt.Before(earliest) {
			return command, nil
		}
	}
	command.Apply = true
	command.FailRun = facts.Status == "queued" || facts.Status == "running"
	if command.FailRun && code == "" {
		command.FailureCode = "processing_incomplete"
	}
	return command, nil
}
