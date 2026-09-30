package models

type DocumentImportAcceptanceFacts struct {
	Path      string
	Reference DocumentFileReference
}
type DocumentImportDisposition struct {
	State                                                                    string
	Parent                                                                   bool
	MessagesAccepted, MessagesReused, AttachmentsAccepted, AttachmentsReused int64
}
type DocumentImportAcceptanceCommand struct {
	Expected                         DocumentImportAcceptanceFacts
	Metadata                         DocumentMetadata
	Created, Reused                  DocumentImportDisposition
	ProcessingState, ProcessingStage string
}

func PlanDocumentImportAcceptance(facts DocumentImportAcceptanceFacts, metadata DocumentMetadata) (DocumentImportAcceptanceCommand, error) {
	command := DocumentImportAcceptanceCommand{Expected: facts, Metadata: metadata, ProcessingState: "queued", ProcessingStage: "queued"}
	if facts.Reference.File.SHA256 == "" {
		return command, ErrConflict
	}
	root := facts.Path == "0"
	if root && facts.Reference.File.MediaType != "message/rfc822" || !root && facts.Reference.File.MediaType == "message/rfc822" {
		return command, ErrUnsupportedMedia
	}
	command.Created = DocumentImportDisposition{State: "accepted", Parent: root}
	command.Reused = DocumentImportDisposition{State: "reused", Parent: root}
	if root {
		command.Created.MessagesAccepted = 1
		command.Reused.MessagesReused = 1
	} else {
		command.Created.AttachmentsAccepted = 1
		command.Reused.AttachmentsReused = 1
	}
	return command, nil
}
