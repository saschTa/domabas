package models

type EmailStartCommand struct {
	Input    EmailStartRun
	Expected EmailProvider
	Trigger  string
}

func PlanEmailStart(facts EmailProviderUpdateFacts, input EmailStartRun, credentialRevision int64) (EmailStartCommand, error) {
	command := EmailStartCommand{Input: input, Expected: facts.Provider, Trigger: "manual"}
	if !facts.VaultAvailable || !facts.CredentialsAvailable {
		return command, ErrUnavailable
	}
	if input.ExpectedRevision != facts.Provider.Revision || !facts.Provider.Enabled || facts.Provider.ConsentRevision != credentialRevision {
		return command, ErrConflict
	}
	return command, nil
}
