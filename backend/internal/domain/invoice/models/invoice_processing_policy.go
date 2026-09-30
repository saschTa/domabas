package models

import (
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	"slices"
)

func PlanInvoiceWork(work InvoiceWork) (InvoiceWork, error) {
	if work.Done {
		return work, nil
	}
	if work.Job.AIAttempt > 0 {
		work.ResumeStage = "enriching"
		return work, nil
	}
	if !slices.Contains([]string{"invoicing", "enriching", "embedding", "finalizing"}, work.Stage) {
		return InvoiceWork{}, d.ErrStaleJob
	}
	if work.Stage != "invoicing" {
		work.ResumeStage = work.Stage
	}
	return work, nil
}

func PlanInvoiceSave(work InvoiceWork, invoice *Invoice) (InvoiceWork, *Invoice, error) {
	if invoice != nil {
		if err := invoice.Validate(); err != nil {
			return work, nil, d.DocumentProcessingError{Code: "invalid_invoice"}
		}
		if !InvoiceEvidenceCanReplace(work.ExistingSource, invoice.Source) {
			work.Skipped = true
			invoice = nil
		}
	}
	work.RemovePreviousAI = invoice == nil && !work.Skipped && work.ExistingSource != "structured" && work.ClassifierVersion == 0
	return work, invoice, nil
}
