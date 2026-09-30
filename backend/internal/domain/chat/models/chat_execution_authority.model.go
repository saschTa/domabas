package models

type ChatExecutionAuthority struct {
	Actor           ChatActor
	EvidencePresent bool
	EvidenceMissing bool
}
