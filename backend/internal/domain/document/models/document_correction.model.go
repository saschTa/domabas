package models

import "math"

type DocumentCorrectionFacts struct {
	Revision, Generation int64
	Location             string
	Configuration        DocumentProcessingConfiguration
}
type DocumentCorrectionCommand struct {
	Expected     DocumentCorrectionFacts
	Text         string
	Chunks       []DocumentChunk
	State, Stage string
}

func PlanDocumentCorrection(facts DocumentCorrectionFacts, input DocumentOCRCorrection) (DocumentCorrectionCommand, error) {
	chunks, err := input.Validate()
	if err != nil {
		return DocumentCorrectionCommand{}, err
	}
	if facts.Revision != input.Revision || facts.Revision == math.MaxInt64 || facts.Generation == math.MaxInt64 {
		return DocumentCorrectionCommand{}, ErrConflict
	}
	command := DocumentCorrectionCommand{Expected: facts, Text: input.Text, Chunks: chunks, State: "queued", Stage: "embedding"}
	if len(chunks) == 0 {
		command.Stage = "finalizing"
		if facts.Location == "final" {
			command.State = "ready"
			command.Stage = "complete"
		}
	}
	return command, nil
}
