package workflows

import (
	"go.temporal.io/sdk/workflow"
	"time"
)

func documentExtractionTimeout(ctx workflow.Context, previous time.Duration) time.Duration {
	if workflow.GetVersion(ctx, "document-extraction-capacity-wait", workflow.DefaultVersion, 1) != workflow.DefaultVersion {
		return 10 * 365 * 24 * time.Hour
	}
	return previous
}

func documentProviderAttempts(ctx workflow.Context, stage string) int32 {
	switch stage {
	case InvoiceDocumentActivity, EnrichDocumentActivity, EmbedDocumentActivity:
		if workflow.GetVersion(ctx, "document-provider-four-retries", workflow.DefaultVersion, 1) != workflow.DefaultVersion {
			return 5
		}
	}
	return 3
}
