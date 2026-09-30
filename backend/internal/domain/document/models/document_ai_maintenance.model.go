package models

type DocumentAIMaintenanceCandidate struct {
	AccountID, DocumentID                 string
	Sequence, LatestConfigurationRevision int64
	Facts                                 DocumentAIEnqueueFacts
}
type DocumentAIMaintenanceFacts struct {
	Revision, Cutoff *int64
	Cursor           int64
	Configuration    DocumentProcessingConfiguration
	Candidates       []DocumentAIMaintenanceCandidate
}
type DocumentAIMaintenanceEnqueue struct {
	AccountID, DocumentID string
	Command               DocumentAIEnqueueCommand
}
type DocumentAIMaintenanceCommand struct {
	Expected DocumentAIMaintenanceFacts
	Cursor   int64
	Complete bool
	Enqueue  []DocumentAIMaintenanceEnqueue
}

func PlanDocumentAIMaintenance(facts DocumentAIMaintenanceFacts) DocumentAIMaintenanceCommand {
	command := DocumentAIMaintenanceCommand{Expected: facts, Cursor: facts.Cursor, Complete: len(facts.Candidates) < 100}
	if facts.Revision == nil || facts.Cutoff == nil {
		return command
	}
	for _, candidate := range facts.Candidates {
		if candidate.Facts.State == "ready" && candidate.LatestConfigurationRevision < *facts.Revision {
			command.Enqueue = append(command.Enqueue, DocumentAIMaintenanceEnqueue{AccountID: candidate.AccountID, DocumentID: candidate.DocumentID, Command: PlanDocumentAIEnqueue(candidate.Facts, facts.Configuration)})
		}
		command.Cursor = candidate.Sequence
	}
	return command
}
