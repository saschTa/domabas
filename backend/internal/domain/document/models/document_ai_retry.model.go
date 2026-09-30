package models

type DocumentAIEnqueueFacts struct {
	State                                  string
	Generation, OCRRevision, LatestAttempt int64
	HasInvoiceEvidence, ManualText         bool
	LatestStatus                           string
}
type DocumentAIRetryFacts struct {
	Enqueue                                       DocumentAIEnqueueFacts
	Configuration                                 DocumentProcessingConfiguration
	RequestExists, RequestCollision               bool
	RequestOwner, RequestDocument, RequestAccount string
	RequestRevision                               int64
	Existing                                      DocumentAIProcessing
}
type DocumentAIEnqueueCommand struct {
	Expected                  DocumentAIEnqueueFacts
	Configuration             DocumentProcessingConfiguration
	Status, Stage, TextSource string
	Finished                  bool
}
type DocumentAIRetryCommand struct {
	Expected  DocumentAIRetryFacts
	Enqueue   DocumentAIEnqueueCommand
	RequestID string
}

func PlanDocumentAIEnqueue(facts DocumentAIEnqueueFacts, c DocumentProcessingConfiguration) DocumentAIEnqueueCommand {
	command := DocumentAIEnqueueCommand{Expected: facts, Configuration: c, Status: "skipped", Stage: "complete", TextSource: "machine", Finished: true}
	if c.LLM.Enabled || c.LLM.InvoiceExtractionEnabled() || facts.HasInvoiceEvidence {
		command.Status = "queued"
		command.Stage = "queued"
		command.Finished = false
	}
	if facts.ManualText {
		command.TextSource = "manual"
	}
	return command
}
func PlanDocumentAIRetry(actor DocumentActor, id string, input DocumentReindexRequest, facts DocumentAIRetryFacts) (DocumentAIRetryCommand, *DocumentAIProcessing, error) {
	command := DocumentAIRetryCommand{Expected: facts, RequestID: input.RequestID}
	if err := ValidateAccountID(input.RequestID); err != nil {
		return command, nil, err
	}
	if facts.RequestExists {
		if facts.RequestOwner != actor.UserID || facts.RequestDocument != id || facts.RequestAccount != actor.AccountID {
			return command, nil, ErrNotFound
		}
		if facts.RequestRevision != input.ConfigurationRevision {
			return command, nil, ErrConflict
		}
		return command, &facts.Existing, nil
	}
	if facts.RequestCollision || facts.Configuration.Revision != input.ConfigurationRevision || facts.Enqueue.State != "ready" || facts.Enqueue.LatestStatus == "queued" || facts.Enqueue.LatestStatus == "running" {
		return command, nil, ErrConflict
	}
	command.Enqueue = PlanDocumentAIEnqueue(facts.Enqueue, facts.Configuration)
	return command, nil, nil
}
