package models

type DocumentAICompletionFacts struct {
	Status, Stage string
	Current       bool
}

func (facts DocumentAICompletionFacts) CompletionReplay() (bool, error) {
	if facts.Status == "succeeded" {
		return true, nil
	}
	if !facts.Current || facts.Stage != "complete" || (facts.Status != "queued" && facts.Status != "running") {
		return false, ErrStaleJob
	}
	return false, nil
}
