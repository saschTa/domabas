package models

type DocumentUnlockFacts struct {
	Reference          DocumentFileReference
	Generation         int64
	State, FailureCode string
}

func (facts DocumentUnlockFacts) Validate(generation int64) error {
	if facts.Generation != generation || facts.State != "failed" || facts.FailureCode != "encrypted_pdf" || facts.Reference.File.MediaType != "application/pdf" || facts.Reference.Location == "unlocked" {
		return ErrConflict
	}
	return nil
}
