package models

type DocumentExecutionRecoveryPlan struct{ Close bool }

type DocumentExecutionFacts struct {
	RunID       string
	SafeMissing bool
}
type DocumentExecutionResolution struct {
	ExpectedRunID, RunID, Outcome string
	Close, Missing                bool
}

func PlanDocumentExecutionRecovery(currentRun, observedRun, outcome string, missing, safeMissing bool) (DocumentExecutionRecoveryPlan, error) {
	if outcome != "" && !ValidFailureCode(outcome) {
		return DocumentExecutionRecoveryPlan{}, DocumentValidationError{Message: "invalid execution outcome"}
	}
	if currentRun != "" && observedRun != "" && currentRun != observedRun {
		return DocumentExecutionRecoveryPlan{}, ErrStaleJob
	}
	return DocumentExecutionRecoveryPlan{Close: outcome != "" && (!missing || safeMissing)}, nil
}
