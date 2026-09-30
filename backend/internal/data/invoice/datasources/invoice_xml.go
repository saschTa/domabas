package datasources

import (
	"bytes"
	"context"
	"encoding/xml"
	"io"
	"strings"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

func invalidInvoice() error { return document.DocumentProcessingError{Code: "invalid_invoice"} }
func ParseXML(ctx context.Context, data []byte) (*m.Invoice, error) {
	if len(data) == 0 || len(data) > 2<<20 {
		return nil, invalidInvoice()
	}
	decoder := xml.NewDecoder(bytes.NewReader(data))
	var root *invoiceXmlNode
	var stack []*invoiceXmlNode
	nodes := 0
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, invalidInvoice()
		}
		switch t := token.(type) {
		case xml.Directive:
			return nil, invalidInvoice()
		case xml.StartElement:
			nodes++
			if nodes > 30000 || len(stack) >= 64 {
				return nil, invalidInvoice()
			}
			n := &invoiceXmlNode{name: t.Name, attrs: t.Attr}
			if len(stack) == 0 {
				if root != nil {
					return nil, invalidInvoice()
				}
				root = n
			} else {
				parent := stack[len(stack)-1]
				parent.children = append(parent.children, n)
			}
			stack = append(stack, n)
		case xml.EndElement:
			if len(stack) == 0 {
				return nil, invalidInvoice()
			}
			stack = stack[:len(stack)-1]
		case xml.CharData:
			if len(stack) > 0 {
				stack[len(stack)-1].text += string(t)
			} else if strings.TrimSpace(string(t)) != "" {
				return nil, invalidInvoice()
			}
		}
	}
	if root == nil || len(stack) != 0 {
		return nil, invalidInvoice()
	}
	var v m.Invoice
	switch {
	case root.name.Local == "CrossIndustryInvoice" && root.name.Space == "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100":
		v = cii(root, false)
	case root.name.Local == "CrossIndustryDocument" && root.name.Space == "urn:ferd:CrossIndustryDocument:invoice:1p0":
		v = cii(root, true)
	case root.name.Local == "Invoice" && root.name.Space == "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2":
		v = ubl(root, false)
	case root.name.Local == "CreditNote" && root.name.Space == "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2":
		v = ubl(root, true)
	default:
		return nil, invalidInvoice()
	}
	v.Source = "structured"
	normalizeXMLDecimals(&v)
	if v.TotalGross == "" || !validXMLValues(root, v.Currency, v.TaxCurrency) {
		return nil, invalidInvoice()
	}
	if err := validateInvoice(v); err != nil {
		return nil, invalidInvoice()
	}
	return &v, nil
}
func knownSpace(s string) bool {
	switch s {
	case "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100", "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100", "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100", "urn:un:unece:uncefact:data:standard:QualifiedDataType:100", "urn:ferd:CrossIndustryDocument:invoice:1p0", "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:12", "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:15", "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2", "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2":
		return true
	}
	return false
}
func (n *invoiceXmlNode) child(name string) *invoiceXmlNode {
	for _, c := range n.children {
		if c.name.Local == name && knownSpace(c.name.Space) {
			return c
		}
	}
	return &invoiceXmlNode{}
}
func (n *invoiceXmlNode) all(name string) []*invoiceXmlNode {
	result := []*invoiceXmlNode{}
	for _, c := range n.children {
		if c.name.Local == name && knownSpace(c.name.Space) {
			result = append(result, c)
		}
	}
	return result
}
func (n *invoiceXmlNode) value(path ...string) string {
	for _, p := range path {
		n = n.child(p)
	}
	return strings.TrimSpace(n.text)
}
func (n *invoiceXmlNode) attr(name string) string {
	for _, a := range n.attrs {
		if a.Name.Local == name && a.Name.Space == "" {
			return a.Value
		}
	}
	return ""
}
func first(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
func ciiDate(n *invoiceXmlNode) string {
	d := n.child("DateTimeString")
	v := d.value()
	if v == "" {
		return ""
	}
	if d.attr("format") == "102" && len(v) == 8 {
		return v[:4] + "-" + v[4:6] + "-" + v[6:]
	}
	return v
}
func ciiParty(n *invoiceXmlNode) m.InvoiceParty {
	address := n.child("PostalTradeAddress")
	v := m.InvoiceParty{Name: n.value("Name"), RegistrationID: n.value("SpecifiedLegalOrganization", "ID"), Country: address.value("CountryID"), Email: n.value("URIUniversalCommunication", "URIID")}
	var parts []string
	for _, key := range []string{"LineOne", "LineTwo", "LineThree", "PostcodeCode", "CityName", "CountrySubDivisionName"} {
		if value := address.value(key); value != "" {
			parts = append(parts, value)
		}
	}
	v.Address = strings.Join(parts, ", ")
	for _, tax := range n.all("SpecifiedTaxRegistration") {
		id := tax.child("ID")
		if id.attr("schemeID") == "VA" {
			v.TaxID = id.value()
		} else if v.RegistrationID == "" {
			v.RegistrationID = id.value()
		}
	}
	return v
}
func cii(root *invoiceXmlNode, legacy bool) m.Invoice {
	header, transaction, agreement, settlement, summary, contextName := "ExchangedDocument", "SupplyChainTradeTransaction", "ApplicableHeaderTradeAgreement", "ApplicableHeaderTradeSettlement", "SpecifiedTradeSettlementHeaderMonetarySummation", "ExchangedDocumentContext"
	if legacy {
		header, transaction, agreement, settlement, summary, contextName = "HeaderExchangedDocument", "SpecifiedSupplyChainTradeTransaction", "ApplicableSupplyChainTradeAgreement", "ApplicableSupplyChainTradeSettlement", "SpecifiedTradeSettlementMonetarySummation", "SpecifiedExchangedDocumentContext"
	}
	h := root.child(header)
	t := root.child(transaction)
	a := t.child(agreement)
	s := t.child(settlement)
	totals := s.child(summary)
	v := m.Invoice{Format: "cii", Number: h.value("ID"), TypeCode: h.value("TypeCode"), IssueDate: ciiDate(h.child("IssueDateTime")), Profile: root.value(contextName, "GuidelineSpecifiedDocumentContextParameter", "ID"), Currency: s.value("InvoiceCurrencyCode"), TaxCurrency: s.value("TaxCurrencyCode"), Seller: ciiParty(a.child("SellerTradeParty")), Buyer: ciiParty(a.child("BuyerTradeParty")), TotalNet: totals.value("TaxBasisTotalAmount"), TotalGross: totals.value("GrandTotalAmount"), AmountDue: totals.value("DuePayableAmount"), PaidAmount: totals.value("TotalPrepaidAmount"), RoundingAmount: totals.value("RoundingAmount")}
	if legacy {
		v.Format = "zugferd-1"
	}
	for _, tax := range totals.all("TaxTotalAmount") {
		currency := tax.attr("currencyID")
		if currency == "" || currency == v.Currency {
			v.TotalTax = tax.value()
		} else if currency == v.TaxCurrency {
			v.TaxAccountingAmount = tax.value()
		}
	}
	for _, term := range s.all("SpecifiedTradePaymentTerms") {
		v.DueDate = first(v.DueDate, ciiDate(term.child("DueDateDateTime")))
		if text := term.value("Description"); text != "" {
			v.Payment.Terms = first(v.Payment.Terms, text)
		}
	}
	means := s.child("SpecifiedTradeSettlementPaymentMeans")
	v.Payment.MeansCode = means.value("TypeCode")
	v.Payment.Reference = s.value("PaymentReference")
	v.Payment.IBAN = means.value("PayeePartyCreditorFinancialAccount", "IBANID")
	v.Payment.BIC = means.value("PayeeSpecifiedCreditorFinancialInstitution", "BICID")
	for _, tax := range s.all("ApplicableTradeTax") {
		v.Taxes = append(v.Taxes, m.InvoiceTax{Category: tax.value("CategoryCode"), Rate: first(tax.value("RateApplicablePercent"), tax.value("ApplicablePercent")), TaxableAmount: tax.value("BasisAmount"), TaxAmount: tax.value("CalculatedAmount"), ExemptionReason: first(tax.value("ExemptionReason"), tax.value("ExemptionReasonCode"))})
	}
	for _, allow := range s.all("SpecifiedTradeAllowanceCharge") {
		v.Allowances = append(v.Allowances, m.InvoiceAllowance{Charge: xmlTrue(allow.value("ChargeIndicator", "Indicator")), Reason: allow.value("Reason"), Amount: allow.value("ActualAmount"), TaxCategory: allow.value("CategoryTradeTax", "CategoryCode"), TaxRate: allow.value("CategoryTradeTax", "RateApplicablePercent")})
	}
	for _, ref := range s.all("InvoiceReferencedDocument") {
		v.References = append(v.References, m.InvoiceReference{Number: first(ref.value("IssuerAssignedID"), ref.value("ID")), IssueDate: first(ciiDate(ref.child("FormattedIssueDateTime")), ciiDate(ref.child("IssueDateTime")))})
	}
	for _, note := range h.all("IncludedNote") {
		if value := note.value("Content"); value != "" {
			v.Notes = append(v.Notes, value)
		}
	}
	for _, line := range t.all("IncludedSupplyChainTradeLineItem") {
		p := line.child("SpecifiedTradeProduct")
		a := line.child("SpecifiedLineTradeAgreement")
		d := line.child("SpecifiedLineTradeDelivery")
		s := line.child("SpecifiedLineTradeSettlement")
		if legacy {
			a = line.child("SpecifiedSupplyChainTradeAgreement")
			d = line.child("SpecifiedSupplyChainTradeDelivery")
			s = line.child("SpecifiedSupplyChainTradeSettlement")
		}
		quantity := d.child("BilledQuantity")
		tax := s.child("ApplicableTradeTax")
		v.Lines = append(v.Lines, m.InvoiceLine{ID: line.value("AssociatedDocumentLineDocument", "LineID"), Description: first(p.value("Name"), p.value("Description")), Quantity: quantity.value(), UnitCode: quantity.attr("unitCode"), UnitPrice: a.value("NetPriceProductTradePrice", "ChargeAmount"), NetAmount: s.value("SpecifiedTradeSettlementLineMonetarySummation", "LineTotalAmount"), TaxCategory: tax.value("CategoryCode"), TaxRate: first(tax.value("RateApplicablePercent"), tax.value("ApplicablePercent"))})
	}
	return v
}
func ublParty(n *invoiceXmlNode) m.InvoiceParty {
	p := n.child("Party")
	a := p.child("PostalAddress")
	var address []string
	for _, key := range []string{"StreetName", "AdditionalStreetName", "CityName", "PostalZone", "CountrySubentity"} {
		if x := a.value(key); x != "" {
			address = append(address, x)
		}
	}
	for _, line := range a.all("AddressLine") {
		address = append(address, line.value("Line"))
	}
	return m.InvoiceParty{Name: first(p.value("PartyLegalEntity", "RegistrationName"), p.value("PartyName", "Name")), TaxID: p.value("PartyTaxScheme", "CompanyID"), RegistrationID: p.value("PartyLegalEntity", "CompanyID"), Address: strings.Join(address, ", "), Country: a.value("Country", "IdentificationCode"), Email: p.value("Contact", "ElectronicMail")}
}
func ubl(root *invoiceXmlNode, credit bool) m.Invoice {
	typeKey, lineKey, quantityKey := "InvoiceTypeCode", "InvoiceLine", "InvoicedQuantity"
	if credit {
		typeKey, lineKey, quantityKey = "CreditNoteTypeCode", "CreditNoteLine", "CreditedQuantity"
	}
	t := root.child("LegalMonetaryTotal")
	v := m.Invoice{Format: "ubl", Profile: root.value("CustomizationID"), Number: root.value("ID"), TypeCode: root.value(typeKey), IssueDate: root.value("IssueDate"), DueDate: root.value("DueDate"), Currency: root.value("DocumentCurrencyCode"), TaxCurrency: root.value("TaxCurrencyCode"), Seller: ublParty(root.child("AccountingSupplierParty")), Buyer: ublParty(root.child("AccountingCustomerParty")), TotalNet: t.value("TaxExclusiveAmount"), TotalGross: t.value("TaxInclusiveAmount"), AmountDue: t.value("PayableAmount"), PaidAmount: t.value("PrepaidAmount"), RoundingAmount: t.value("PayableRoundingAmount")}
	if credit && v.TypeCode == "" {
		v.TypeCode = "381"
	}
	for _, tax := range root.all("TaxTotal") {
		amount := tax.child("TaxAmount")
		c := amount.attr("currencyID")
		if c == v.TaxCurrency && c != v.Currency {
			v.TaxAccountingAmount = amount.value()
			continue
		}
		if c != "" && c != v.Currency {
			v.Currency = ""
			continue
		}
		v.TotalTax = amount.value()
		for _, sub := range tax.all("TaxSubtotal") {
			category := sub.child("TaxCategory")
			v.Taxes = append(v.Taxes, m.InvoiceTax{Category: category.value("ID"), Rate: category.value("Percent"), TaxableAmount: sub.value("TaxableAmount"), TaxAmount: sub.value("TaxAmount"), ExemptionReason: first(category.value("TaxExemptionReason"), category.value("TaxExemptionReasonCode"))})
		}
	}
	for _, ref := range root.all("BillingReference") {
		r := ref.child("InvoiceDocumentReference")
		v.References = append(v.References, m.InvoiceReference{Number: r.value("ID"), IssueDate: r.value("IssueDate")})
	}
	for _, note := range root.all("Note") {
		v.Notes = append(v.Notes, note.value())
	}
	for _, line := range root.all(lineKey) {
		q := line.child(quantityKey)
		tax := line.child("Item").child("ClassifiedTaxCategory")
		v.Lines = append(v.Lines, m.InvoiceLine{ID: line.value("ID"), Description: first(line.value("Item", "Name"), line.value("Item", "Description")), Quantity: q.value(), UnitCode: q.attr("unitCode"), UnitPrice: line.value("Price", "PriceAmount"), NetAmount: line.value("LineExtensionAmount"), TaxCategory: tax.value("ID"), TaxRate: tax.value("Percent")})
	}
	for _, allow := range root.all("AllowanceCharge") {
		v.Allowances = append(v.Allowances, m.InvoiceAllowance{Charge: xmlTrue(allow.value("ChargeIndicator")), Reason: allow.value("AllowanceChargeReason"), Amount: allow.value("Amount"), TaxCategory: allow.value("TaxCategory", "ID"), TaxRate: allow.value("TaxCategory", "Percent")})
	}
	p := root.child("PaymentMeans")
	v.Payment = m.InvoicePayment{MeansCode: p.value("PaymentMeansCode"), Reference: p.value("PaymentID"), IBAN: p.value("PayeeFinancialAccount", "ID"), BIC: p.value("PayeeFinancialAccount", "FinancialInstitutionBranch", "ID"), Terms: root.value("PaymentTerms", "Note")}
	v.DueDate = first(v.DueDate, p.value("PaymentDueDate"))
	return v
}

func validXMLValues(n *invoiceXmlNode, invoiceCurrency, taxCurrency string) bool {
	if knownSpace(n.name.Space) {
		if n.name.Local == "ChargeIndicator" {
			switch first(n.value("Indicator"), n.value()) {
			case "true", "false", "1", "0":
			default:
				return false
			}
		}
		if c := n.attr("currencyID"); c != "" && c != invoiceCurrency {
			if c != taxCurrency || (n.name.Local != "TaxTotalAmount" && n.name.Local != "TaxAmount") {
				return false
			}
		}
	}
	for _, child := range n.children {
		if !validXMLValues(child, invoiceCurrency, taxCurrency) {
			return false
		}
	}
	return true
}
