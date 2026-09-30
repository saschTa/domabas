package models

import "time"

type DocumentDeliverySettings struct {
	UnlimitedInference bool
}

type DocumentDeliveryPolicy struct {
	DeliveryWindow, StartRetryWindow, StartPermit, ClaimLease time.Duration
	ExecutionTimeout                                          time.Duration
	WaitForLegacy, PrioritizeEnrolled, AlternateReindex       bool
}

func PlanDocumentDelivery(settings DocumentDeliverySettings) DocumentDeliveryPolicy {
	policy := DocumentDeliveryPolicy{DeliveryWindow: 24 * time.Hour, StartRetryWindow: 23*time.Hour + 59*time.Minute, StartPermit: 5 * time.Second, ClaimLease: 30 * time.Second, ExecutionTimeout: 15 * time.Minute, WaitForLegacy: true, PrioritizeEnrolled: true, AlternateReindex: true}
	if settings.UnlimitedInference {
		policy.ExecutionTimeout = 0
	}
	return policy
}
