package models

type DocumentReindexExistingRequest struct {
	AccountID, RequesterID *string
	ConfigurationRevision  int64
}

type DocumentReindexStartFacts struct {
	ConfigurationRevision    int64
	ConfigurationFingerprint string
	Existing                 *DocumentReindexExistingRequest
	Active                   bool
}

type DocumentReindexStartCommand struct {
	Expected DocumentReindexStartFacts
	Request  DocumentReindexRequest
	Replay   bool
}

func PlanDocumentReindexStart(a DocumentActor, system bool, input DocumentReindexRequest, facts DocumentReindexStartFacts) (DocumentReindexStartCommand, error) {
	command := DocumentReindexStartCommand{Expected: facts, Request: input}
	if existing := facts.Existing; existing != nil {
		correctScope := (system && existing.AccountID == nil) || (!system && existing.AccountID != nil && *existing.AccountID == a.AccountID)
		if !correctScope || existing.RequesterID == nil || *existing.RequesterID != a.UserID {
			return command, ErrNotFound
		}
		if existing.ConfigurationRevision != input.ConfigurationRevision {
			return command, ErrConflict
		}
		command.Replay = true
		return command, nil
	}
	if facts.ConfigurationRevision != input.ConfigurationRevision || facts.Active {
		return command, ErrConflict
	}
	return command, nil
}
