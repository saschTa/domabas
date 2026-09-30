package models

import "time"

type DocumentUploadAcceptanceFacts struct {
	State     string
	ExpiresAt time.Time
	Reference DocumentFileReference
}
type DocumentUploadAcceptanceCommand struct {
	Expected                                           DocumentUploadAcceptanceFacts
	Metadata                                           DocumentMetadata
	CreatedAt                                          time.Time
	ProcessingState, ProcessingStage, ReservationState string
}

func PlanDocumentUploadAcceptance(facts DocumentUploadAcceptanceFacts, metadata DocumentMetadata, now time.Time) (DocumentUploadAcceptanceCommand, error) {
	command := DocumentUploadAcceptanceCommand{Expected: facts, Metadata: metadata, CreatedAt: now, ProcessingState: "queued", ProcessingStage: "queued", ReservationState: "accepted"}
	if facts.State != "receiving" || !facts.ExpiresAt.After(now) || facts.Reference.File.SHA256 == "" {
		return command, ErrConflict
	}
	return command, nil
}
