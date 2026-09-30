package models

import "time"

type PaperlessRunFacts struct {
	State, Stage       string
	Cancelled, Started bool
	UpdatedAt          time.Time
}

type PaperlessWorkCommand struct {
	Expected         PaperlessRunFacts
	Active, Retrieve bool
	State, Stage     string
	Retrieval        PaperlessRetrievalPolicy
}

func PlanPaperlessWork(facts PaperlessRunFacts) PaperlessWorkCommand {
	command := PaperlessWorkCommand{Expected: facts, State: facts.State, Stage: facts.Stage, Retrieval: DefaultPaperlessRetrievalPolicy()}
	if facts.Cancelled || (facts.State != "queued" && facts.State != "running") {
		return command
	}
	command.Active = true
	command.State = "running"
	if command.Stage == "queued" {
		command.Stage = "discovering"
	}
	command.Retrieve = command.Stage == "importing"
	return command
}

type PaperlessTerminalCommand struct {
	Expected                                       PaperlessRunFacts
	State, Stage, Code                             string
	Cancel, ClearCredential, CloseExecution, Apply bool
}

func PlanPaperlessCancellation(facts PaperlessRunFacts) PaperlessTerminalCommand {
	command := PaperlessTerminalCommand{Expected: facts, State: facts.State, Stage: facts.Stage}
	if facts.State != "queued" && facts.State != "running" {
		return command
	}
	command.Apply = true
	command.Cancel = true
	if facts.State == "queued" {
		command.State = "cancelled"
		command.Stage = "complete"
		command.ClearCredential = true
		command.CloseExecution = !facts.Started
	}
	return command
}

func PlanPaperlessFinish(facts PaperlessRunFacts, state, code string) (PaperlessTerminalCommand, error) {
	command := PaperlessTerminalCommand{Expected: facts, State: state, Stage: "complete", Code: code, ClearCredential: true}
	if state != "succeeded" && state != "failed" && state != "cancelled" {
		return command, PaperlessFailure{Code: "invalid_terminal_state"}
	}
	if facts.State != "queued" && facts.State != "running" {
		return command, nil
	}
	command.Apply = true
	if facts.Cancelled {
		command.State = "cancelled"
	}
	return command, nil
}
