package models

import "math"

type DocumentRetryFacts struct {
	Generation     int64
	State          string
	HasMachineText bool
	Configuration  DocumentProcessingConfiguration
}

type DocumentRetryCommand struct {
	Expected   DocumentRetryFacts
	Generation int64
}

func PlanDocumentRetry(facts DocumentRetryFacts) (DocumentRetryCommand, error) {
	if facts.State != "failed" && !(facts.State == "ready" && !facts.HasMachineText) {
		return DocumentRetryCommand{}, ErrConflict
	}
	if facts.Generation == math.MaxInt64 {
		return DocumentRetryCommand{}, ErrConflict
	}
	return DocumentRetryCommand{Expected: facts, Generation: facts.Generation + 1}, nil
}
