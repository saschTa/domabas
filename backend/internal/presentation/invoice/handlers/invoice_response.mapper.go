package handlers

import (
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func invoiceResponseMapper(v m.Invoice) contract.Invoice {
	out := contract.Invoice{Id: uuid.MustParse(v.ID), DocumentId: uuid.MustParse(v.DocumentID), DocumentTitle: v.DocumentTitle, Source: v.Source, Format: v.Format, Number: v.Number, TypeCode: v.TypeCode, IssueDate: v.IssueDate, DueDate: v.DueDate, Currency: v.Currency, TaxCurrency: v.TaxCurrency, TotalNet: v.TotalNet, TotalTax: v.TotalTax, TotalGross: v.TotalGross, AmountDue: v.AmountDue, PaidAmount: v.PaidAmount, RoundingAmount: v.RoundingAmount, TaxAccountingAmount: v.TaxAccountingAmount, Profile: v.Profile, ExtractionModel: v.ExtractionModel, CreatedAt: v.CreatedAt, Seller: invoicePartyResponseMapper(v.Seller), Buyer: invoicePartyResponseMapper(v.Buyer), Payment: contract.InvoicePayment{MeansCode: v.Payment.MeansCode, Reference: v.Payment.Reference, Iban: v.Payment.IBAN, Bic: v.Payment.BIC, Terms: v.Payment.Terms}, Lines: []contract.InvoiceLine{}, Taxes: []contract.InvoiceTax{}, Allowances: []contract.InvoiceAllowance{}, References: []contract.InvoiceReference{}, Notes: append([]string{}, v.Notes...)}
	for _, l := range v.Lines {
		out.Lines = append(out.Lines, contract.InvoiceLine{Id: l.ID, Description: l.Description, Quantity: l.Quantity, UnitCode: l.UnitCode, UnitPrice: l.UnitPrice, NetAmount: l.NetAmount, TaxCategory: l.TaxCategory, TaxRate: l.TaxRate})
	}
	for _, t := range v.Taxes {
		out.Taxes = append(out.Taxes, contract.InvoiceTax{Category: t.Category, Rate: t.Rate, TaxableAmount: t.TaxableAmount, TaxAmount: t.TaxAmount, ExemptionReason: t.ExemptionReason})
	}
	for _, a := range v.Allowances {
		out.Allowances = append(out.Allowances, contract.InvoiceAllowance{Charge: a.Charge, Reason: a.Reason, Amount: a.Amount, TaxCategory: a.TaxCategory, TaxRate: a.TaxRate})
	}
	for _, r := range v.References {
		ref := contract.InvoiceReference{Number: r.Number, IssueDate: r.IssueDate}
		if id, err := uuid.Parse(r.InvoiceID); err == nil {
			ref.InvoiceId = &id
		}
		if id, err := uuid.Parse(r.DocumentID); err == nil {
			ref.DocumentId = &id
		}
		out.References = append(out.References, ref)
	}
	return out
}

func invoicePartyResponseMapper(p m.InvoiceParty) contract.InvoiceParty {
	return contract.InvoiceParty{Name: p.Name, TaxId: p.TaxID, RegistrationId: p.RegistrationID, Address: p.Address, Country: p.Country, Email: p.Email}
}
