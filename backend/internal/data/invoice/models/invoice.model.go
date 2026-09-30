package models

import "time"

type InvoiceRecord struct {
	ID, DocumentID, DocumentTitle, Source, Format                                              string
	Number, TypeCode, IssueDate, DueDate, Currency, TaxCurrency                                string
	TotalNet, TotalTax, TotalGross, AmountDue, PaidAmount, RoundingAmount, TaxAccountingAmount string
	Profile, ExtractionModel                                                                   string
	Seller, Buyer                                                                              InvoicePartyRecord
	Payment                                                                                    InvoicePaymentRecord
	Lines                                                                                      []InvoiceLineRecord
	Taxes                                                                                      []InvoiceTaxRecord
	Allowances                                                                                 []InvoiceAllowanceRecord
	References                                                                                 []InvoiceReferenceRecord
	Notes                                                                                      []string
	CreatedAt                                                                                  time.Time
	Score                                                                                      float64
}
type InvoicePartyRecord struct{ Name, TaxID, RegistrationID, Address, Country, Email string }
type InvoicePaymentRecord struct{ MeansCode, Reference, IBAN, BIC, Terms string }
type InvoiceLineRecord struct{ ID, Description, Quantity, UnitCode, UnitPrice, NetAmount, TaxCategory, TaxRate string }
type InvoiceTaxRecord struct{ Category, Rate, TaxableAmount, TaxAmount, ExemptionReason string }
type InvoiceAllowanceRecord struct {
	Charge                               bool
	Reason, Amount, TaxCategory, TaxRate string
}
type InvoiceReferenceRecord struct{ Number, IssueDate, InvoiceID, DocumentID string }
type InvoiceRecordPage struct {
	Items      []InvoiceRecord
	NextCursor string
}
