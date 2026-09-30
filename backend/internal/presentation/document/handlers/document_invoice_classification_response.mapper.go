package handlers

import "github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"

func documentInvoiceClassificationResponseMapper(decision, reason string, pass, input, source int) *contract.InvoiceClassification {
	if decision == "" {
		return nil
	}
	return &contract.InvoiceClassification{Decision: contract.InvoiceClassificationDecision(decision), Reason: reason, Pass: pass, InputCharacters: input, SourceCharacters: source}
}
