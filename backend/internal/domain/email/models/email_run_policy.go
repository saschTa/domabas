package models

import "time"

type EmailRunFinishFacts struct {
	Work       EmailWork
	RetryCount int
}

type EmailRunFinishCommand struct {
	Facts               EmailRunFinishFacts
	Status, Stage, Code string
	More                bool
	Delay               time.Duration
	RetryCount          int
}

func PlanEmailRunFinish(facts EmailRunFinishFacts, more bool, code string) EmailRunFinishCommand {
	run := facts.Work.Run
	command := EmailRunFinishCommand{Facts: facts, Status: "succeeded", Stage: "complete", Code: code, More: more, Delay: time.Duration(facts.Work.Provider.IntervalMinutes) * time.Minute}
	if run.MessagesFailed > 0 || run.MessagesWithContentFailures > 0 || run.AttachmentsFailed > 0 {
		command.Status = "partial"
		if run.MessagesAccepted+run.MessagesReused+run.AttachmentsAccepted+run.AttachmentsReused == 0 {
			command.Status = "failed"
		}
	}
	if more {
		command.Delay = time.Second
	}
	if code != "" {
		command.Status = "failed"
		command.Stage = run.Stage
		command.Delay = min(time.Duration(facts.Work.Provider.IntervalMinutes)*time.Minute, time.Minute*time.Duration(1<<min(facts.RetryCount, 10)))
		command.RetryCount = facts.RetryCount + 1
	}
	return command
}
