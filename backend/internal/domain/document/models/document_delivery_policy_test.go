package models

import (
	"testing"
	"time"
)

func TestDocumentDeliveryKeepsPermitInsideStartWindow(t *testing.T) {
	policy := PlanDocumentDelivery(DocumentDeliverySettings{})
	if policy.StartRetryWindow+policy.StartPermit >= policy.DeliveryWindow || policy.ClaimLease <= policy.StartPermit || policy.ExecutionTimeout != 15*time.Minute {
		t.Fatalf("unsafe bounded delivery policy: %+v", policy)
	}
	if !policy.WaitForLegacy || !policy.PrioritizeEnrolled || !policy.AlternateReindex {
		t.Fatalf("admission precedence changed: %+v", policy)
	}
	unlimited := PlanDocumentDelivery(DocumentDeliverySettings{UnlimitedInference: true})
	if unlimited.ExecutionTimeout != 0 || unlimited.DeliveryWindow != policy.DeliveryWindow || unlimited.StartRetryWindow != policy.StartRetryWindow {
		t.Fatalf("unbounded inference weakened delivery window: %+v", unlimited)
	}
}
