package models

type InferredInvoice struct {
	Number, TypeCode, IssueDate, DueDate, Currency                        string
	TotalNet, TotalTax, TotalGross, AmountDue, PaidAmount, RoundingAmount string
	Seller, Buyer                                                         InvoicePartyRecord
	Payment                                                               InvoicePaymentRecord
	Lines                                                                 []InvoiceLineRecord
	Taxes                                                                 []InvoiceTaxRecord
	Allowances                                                            []InvoiceAllowanceRecord
	References                                                            []InvoiceInferredReference
	Notes                                                                 []string
	VATAccounting                                                         *InvoiceInferredAccountingTax
}

type InvoiceInferredReference struct{ Number, IssueDate string }

type InvoiceInferredAccountingTax struct{ Currency, Amount string }
