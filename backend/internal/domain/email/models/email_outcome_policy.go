package models

import "time"

type EmailMessageFacts struct {
	State, ParentDocumentID, LastCountedRunID, InspectionState string
	PendingParts                                               bool
	RetryCount                                                 int
}

type EmailMessageOutcomeCommand struct {
	Expected                     EmailMessageFacts
	State, Code, InspectionState string
	PendingParts, DateOnly       bool
	Failed, Skipped              int64
	RetryDelay                   time.Duration
	InternalDate                 *time.Time
}

func PlanEmailMessageOutcome(facts EmailMessageFacts, runID, state, code string, stamp *time.Time) (EmailMessageOutcomeCommand, error) {
	command := EmailMessageOutcomeCommand{Expected: facts, State: state, Code: code, InspectionState: facts.InspectionState, PendingParts: facts.PendingParts, InternalDate: stamp, RetryDelay: min(24*time.Hour, time.Minute*time.Duration(1<<min(facts.RetryCount, 11)))}
	switch state {
	case "pending", "failed", "skipped", "deleted", "fetched":
	default:
		return command, EmailValidationError{Message: "invalid message outcome"}
	}
	if state == "fetched" {
		command.DateOnly = true
		return command, nil
	}
	if facts.ParentDocumentID == "" && facts.LastCountedRunID != runID {
		if state == "skipped" || state == "deleted" {
			command.Skipped = 1
		} else {
			command.Failed = 1
		}
	}
	if facts.ParentDocumentID != "" && state != "deleted" {
		command.State = facts.State
	}
	if state == "failed" || state == "skipped" || state == "deleted" {
		command.InspectionState = "failed"
		command.PendingParts = false
	} else if state == "pending" {
		command.InspectionState = "pending"
	}
	return command, nil
}

type EmailPartFacts struct{ Path, LastCountedRunID, State string }
type EmailPartOutcomeCommand struct {
	Expected        EmailPartFacts
	State, Code     string
	Failed, Skipped int64
	ContentFailure  bool
}

func PlanEmailPartOutcome(facts EmailPartFacts, runID, state, code string) (EmailPartOutcomeCommand, error) {
	command := EmailPartOutcomeCommand{Expected: facts, State: state, Code: code, ContentFailure: state != "skipped"}
	if state != "pending" && state != "failed" && state != "skipped" {
		return command, EmailValidationError{Message: "invalid part outcome"}
	}
	if facts.Path != "0" && facts.LastCountedRunID != runID {
		if state == "skipped" {
			command.Skipped = 1
		} else {
			command.Failed = 1
		}
	}
	return command, nil
}

type EmailInspectionCommand struct {
	State          string
	ContentFailure bool
}

func PlanEmailInspection(complete, failures bool) EmailInspectionCommand {
	command := EmailInspectionCommand{State: "complete", ContentFailure: failures || !complete}
	if !complete {
		command.State = "failed"
	}
	return command
}
