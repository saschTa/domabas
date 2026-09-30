package models

type EmailProviderUpdateFacts struct {
	Provider                             EmailProvider
	Credentials                          EmailCredentials
	CredentialsAvailable, VaultAvailable bool
}

type EmailProviderUpdateCommand struct {
	Input                                                EmailProviderInput
	Expected                                             EmailProvider
	Credentials                                          EmailCredentials
	CredentialChanged, SourceChanged, RenewConsent, Noop bool
	SupersededState, SupersededCode                      string
}

func PlanEmailProviderUpdate(facts EmailProviderUpdateFacts, input EmailProviderInput, revision int64) (EmailProviderUpdateCommand, error) {
	command := EmailProviderUpdateCommand{Input: input, Expected: facts.Provider, Credentials: facts.Credentials, SupersededState: "superseded", SupersededCode: "provider_changed"}
	usernameChanged := false
	if input.Username != nil || input.Password != nil {
		if !facts.VaultAvailable {
			return command, ErrUnavailable
		}
		if !facts.CredentialsAvailable && (input.Username == nil || input.Password == nil) {
			return command, EmailValidationError{Message: "replace both username and password when credentials are unavailable"}
		}
		if input.Username != nil {
			command.Credentials.Username = *input.Username
		}
		if input.Password != nil {
			command.Credentials.Password = *input.Password
		}
		if err := command.Credentials.Validate(); err != nil {
			return command, err
		}
		command.CredentialChanged = !facts.CredentialsAvailable || command.Credentials != facts.Credentials
		usernameChanged = !facts.CredentialsAvailable || command.Credentials.Username != facts.Credentials.Username
	}
	command.RenewConsent = input.Enabled && (!facts.Provider.Enabled || (input.RenewConsent && facts.Provider.ConsentRevision != revision))
	command.SourceChanged = usernameChanged || facts.Provider.Host != input.Host || facts.Provider.Port != input.Port || facts.Provider.Mailbox != input.Mailbox
	command.Noop = facts.Provider.EmailSettings == input.EmailSettings && !command.CredentialChanged && !command.RenewConsent
	if !command.Noop && (input.ExpectedRevision == nil || *input.ExpectedRevision != facts.Provider.Revision) {
		return command, ErrConflict
	}
	return command, nil
}
