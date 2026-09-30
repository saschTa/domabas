package models

import (
	"time"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type Invoice struct {
	ID, DocumentID, DocumentTitle, Source, Format                                              string
	Number, TypeCode, IssueDate, DueDate, Currency, TaxCurrency                                string
	TotalNet, TotalTax, TotalGross, AmountDue, PaidAmount, RoundingAmount, TaxAccountingAmount string
	Profile, ExtractionModel                                                                   string
	Seller, Buyer                                                                              InvoiceParty
	Lines                                                                                      []InvoiceLine
	Taxes                                                                                      []InvoiceTax
	Allowances                                                                                 []InvoiceAllowance
	References                                                                                 []InvoiceReference
	Payment                                                                                    InvoicePayment
	Notes                                                                                      []string
	CreatedAt                                                                                  time.Time
}
type InvoiceParty struct{ Name, TaxID, RegistrationID, Address, Country, Email string }
type InvoiceLine struct{ ID, Description, Quantity, UnitCode, UnitPrice, NetAmount, TaxCategory, TaxRate string }
type InvoiceTax struct{ Category, Rate, TaxableAmount, TaxAmount, ExemptionReason string }
type InvoiceAllowance struct {
	Charge                               bool
	Reason, Amount, TaxCategory, TaxRate string
}
type InvoiceReference struct{ Number, IssueDate, InvoiceID, DocumentID string }
type InvoicePayment struct{ MeansCode, Reference, IBAN, BIC, Terms string }
type InvoicePage struct {
	Items      []Invoice
	NextCursor string
}
type InvoiceQuery struct {
	Limit                                                               int
	Cursor, Source, Text                                                string
	Sort                                                                string
	Number, Seller, Buyer, Currency, TypeCode, Format, PaymentMeansCode string
	CreatedFrom, CreatedTo, IssueFrom, IssueTo, DueFrom, DueTo          string
	TotalMin, TotalMax                                                  string
}
type InvoiceWork struct {
	ClassifierVersion  int
	Classification     InvoiceClassification
	ExistingSource     string
	Stage, ResumeStage string
	RemovePreviousAI   bool
	SourceFailureCode  string
	Skipped            bool
	Job                document.DocumentJob
	Revision           int64
	Done               bool
	MediaType, Text    string
	XML                []byte
	Configuration      document.DocumentLLMConfiguration
}

type InvoiceFilterValueQuery struct {
	Limit               int
	Cursor, Field, Text string
}
type InvoiceFilterValuePage struct {
	Items      []string
	NextCursor string
}
