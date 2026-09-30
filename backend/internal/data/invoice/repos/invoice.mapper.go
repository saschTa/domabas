package repos

import (
	r "github.com/domabas/domabas/backend/internal/data/invoice/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

func invoiceRecordToDomainMapper(v r.InvoiceRecord) m.Invoice {
	result := m.Invoice{ID: v.ID, DocumentID: v.DocumentID, DocumentTitle: v.DocumentTitle, Source: v.Source, Format: v.Format, Number: v.Number, TypeCode: v.TypeCode, IssueDate: v.IssueDate, DueDate: v.DueDate, Currency: v.Currency, TaxCurrency: v.TaxCurrency, TotalNet: v.TotalNet, TotalTax: v.TotalTax, TotalGross: v.TotalGross, AmountDue: v.AmountDue, PaidAmount: v.PaidAmount, RoundingAmount: v.RoundingAmount, TaxAccountingAmount: v.TaxAccountingAmount, Profile: v.Profile, ExtractionModel: v.ExtractionModel, CreatedAt: v.CreatedAt, Notes: append([]string{}, v.Notes...)}
	result.Seller = m.InvoiceParty(v.Seller)
	result.Buyer = m.InvoiceParty(v.Buyer)
	result.Payment = m.InvoicePayment(v.Payment)
	for _, line := range v.Lines {
		result.Lines = append(result.Lines, m.InvoiceLine(line))
	}
	for _, tax := range v.Taxes {
		result.Taxes = append(result.Taxes, m.InvoiceTax(tax))
	}
	for _, allowance := range v.Allowances {
		result.Allowances = append(result.Allowances, m.InvoiceAllowance(allowance))
	}
	for _, reference := range v.References {
		result.References = append(result.References, m.InvoiceReference(reference))
	}
	return result
}

func invoiceDomainToRecordMapper(v m.Invoice) r.InvoiceRecord {
	result := r.InvoiceRecord{ID: v.ID, DocumentID: v.DocumentID, DocumentTitle: v.DocumentTitle, Source: v.Source, Format: v.Format, Number: v.Number, TypeCode: v.TypeCode, IssueDate: v.IssueDate, DueDate: v.DueDate, Currency: v.Currency, TaxCurrency: v.TaxCurrency, TotalNet: v.TotalNet, TotalTax: v.TotalTax, TotalGross: v.TotalGross, AmountDue: v.AmountDue, PaidAmount: v.PaidAmount, RoundingAmount: v.RoundingAmount, TaxAccountingAmount: v.TaxAccountingAmount, Profile: v.Profile, ExtractionModel: v.ExtractionModel, CreatedAt: v.CreatedAt, Notes: append([]string{}, v.Notes...)}
	result.Seller = r.InvoicePartyRecord(v.Seller)
	result.Buyer = r.InvoicePartyRecord(v.Buyer)
	result.Payment = r.InvoicePaymentRecord(v.Payment)
	for _, line := range v.Lines {
		result.Lines = append(result.Lines, r.InvoiceLineRecord(line))
	}
	for _, tax := range v.Taxes {
		result.Taxes = append(result.Taxes, r.InvoiceTaxRecord(tax))
	}
	for _, allowance := range v.Allowances {
		result.Allowances = append(result.Allowances, r.InvoiceAllowanceRecord(allowance))
	}
	for _, reference := range v.References {
		result.References = append(result.References, r.InvoiceReferenceRecord(reference))
	}
	return result
}
