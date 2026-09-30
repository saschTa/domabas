package models

type EmailAttemptAdmission struct {
	Status, Stage string
}

func EmailPageAdmission() EmailAttemptAdmission {
	return EmailAttemptAdmission{Status: "running", Stage: "discovering"}
}

type EmailRetirementCommand struct {
	RunID, Status, Stage, Code string
}

func EmailRevokedRun(runID string) EmailRetirementCommand {
	return EmailRetirementCommand{RunID: runID, Status: "cancelled", Stage: "complete", Code: "authorization_revoked"}
}
