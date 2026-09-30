package models

import "time"

type DocumentUploadRetentionPolicy struct {
	Limit                                                  int
	ClaimLease                                             time.Duration
	ExpiredStates, DurableLocations                        []string
	AcceptedState, RetiringState, ReapingState, ReadyState string
}

func DocumentStagedUploadRetention() DocumentUploadRetentionPolicy {
	return DocumentUploadRetentionPolicy{Limit: 100, ClaimLease: 30 * time.Second, ExpiredStates: []string{"receiving", "reaping", "retiring"}, DurableLocations: []string{"final", "unlocked"}, AcceptedState: "accepted", RetiringState: "retiring", ReapingState: "reaping", ReadyState: "ready"}
}
