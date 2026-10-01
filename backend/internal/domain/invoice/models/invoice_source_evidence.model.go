package models

type InvoiceEvidencePolicy struct{}

type invoiceSourceNumber struct {
	dot, comma string
}

type invoiceSourceSpan struct {
	start, end int
}

type invoiceSourceDate struct {
	span                  invoiceSourceSpan
	year, month, day      int
	separator             byte
	fixedOrder, shortYear bool
}
