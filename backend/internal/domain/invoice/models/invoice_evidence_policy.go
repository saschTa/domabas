package models

func InvoiceEvidenceCanReplace(existing, incoming string) bool {
	return existing != "structured" || incoming == "structured"
}
