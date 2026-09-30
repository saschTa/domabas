package datasources

import (
	"bytes"
	"context"
	"strings"
	"testing"

	fixtures "github.com/domabas/domabas/backend/tests/fixtures/invoices"
)

func TestCIIAndUBLPreserveFinancialEvidence(t *testing.T) {
	v, err := ParseXML(t.Context(), fixtures.CII)
	if err != nil {
		t.Fatal(err)
	}
	if v.Number != "INV-2026-001" || v.IssueDate != "2026-09-19" || v.DueDate != "2026-10-19" || v.Currency != "EUR" || v.TotalGross != "119.00" || v.Seller.TaxID != "DE123456789" || len(v.Lines) != 1 || v.Lines[0].UnitPrice != "10.0000" || len(v.Taxes) != 1 || v.Payment.IBAN != "DE89370400440532013000" {
		t.Fatalf("lost CII evidence: %+v", v)
	}
	v, err = ParseXML(t.Context(), fixtures.UBLCredit)
	if err != nil {
		t.Fatal(err)
	}
	if v.TypeCode != "381" || v.Currency != "KWD" || v.TotalGross != "1.190" || v.TaxCurrency != "EUR" || v.TaxAccountingAmount != "0.55" || v.TotalTax != "0.190" || len(v.References) != 1 || v.References[0].Number != "INV-2026-001" || v.Lines[0].Quantity != "1" {
		t.Fatalf("lost UBL credit evidence: %+v", v)
	}
}
func TestLegacyZUGFeRDAndArbitraryPrefixes(t *testing.T) {
	text := strings.NewReplacer("CrossIndustryInvoice", "CrossIndustryDocument", "urn:un:unece:uncefact:data:standard:CrossIndustryDocument:100", "urn:ferd:CrossIndustryDocument:invoice:1p0", "ReusableAggregateBusinessInformationEntity:100", "ReusableAggregateBusinessInformationEntity:12", "UnqualifiedDataType:100", "UnqualifiedDataType:15", "ExchangedDocumentContext", "SpecifiedExchangedDocumentContext", "<rsm:ExchangedDocument>", "<rsm:HeaderExchangedDocument>", "</rsm:ExchangedDocument>", "</rsm:HeaderExchangedDocument>", "SupplyChainTradeTransaction", "SpecifiedSupplyChainTradeTransaction", "ApplicableHeaderTradeAgreement", "ApplicableSupplyChainTradeAgreement", "ApplicableHeaderTradeSettlement", "ApplicableSupplyChainTradeSettlement", "SpecifiedTradeSettlementHeaderMonetarySummation", "SpecifiedTradeSettlementMonetarySummation").Replace(string(fixtures.CII))
	text = strings.ReplaceAll(text, "urn:un:unece:uncefact:data:standard:CrossIndustryDocument:100", "urn:ferd:CrossIndustryDocument:invoice:1p0")
	v, err := ParseXML(t.Context(), []byte(text))
	if err != nil || v.Format != "zugferd-1" || v.TotalGross != "119.00" {
		t.Fatalf("legacy invoice: %+v %v", v, err)
	}
	text = strings.ReplaceAll(string(fixtures.CII), "ram:", "custom:")
	text = strings.ReplaceAll(text, "xmlns:ram=", "xmlns:custom=")
	if _, err = ParseXML(t.Context(), []byte(text)); err != nil {
		t.Fatal(err)
	}
}

func TestXMLDecimalAndBooleanLexicalForms(t *testing.T) {
	text := strings.NewReplacer(
		"119.00", "+00119.00",
		"10.0000", "00010.0000",
		"<ram:RateApplicablePercent>19<", "<ram:RateApplicablePercent>19.<",
	).Replace(string(fixtures.CII))
	allowance := `<ram:SpecifiedTradeAllowanceCharge><ram:ChargeIndicator><udt:Indicator>1</udt:Indicator></ram:ChargeIndicator><ram:ActualAmount>+.50</ram:ActualAmount></ram:SpecifiedTradeAllowanceCharge>`
	text = strings.Replace(text, "</ram:ApplicableHeaderTradeSettlement>", allowance+"</ram:ApplicableHeaderTradeSettlement>", 1)
	v, err := ParseXML(t.Context(), []byte(text))
	if err != nil {
		t.Fatal(err)
	}
	if v.TotalGross != "119.00" || v.Lines[0].UnitPrice != "10.0000" || v.Lines[0].TaxRate != "19" || len(v.Allowances) != 1 || !v.Allowances[0].Charge || v.Allowances[0].Amount != "0.50" {
		t.Fatalf("XML lexical forms lost financial meaning: %+v", v)
	}
	for _, value := range []string{"yes", "", "2"} {
		invalid := strings.Replace(text, "<udt:Indicator>1</", "<udt:Indicator>"+value+"</", 1)
		if _, err = ParseXML(t.Context(), []byte(invalid)); err == nil {
			t.Fatalf("invalid charge indicator %q accepted", value)
		}
	}
	credit := strings.Replace(string(fixtures.UBLCredit), "</CreditNote>", `<cac:AllowanceCharge><cbc:ChargeIndicator>0</cbc:ChargeIndicator><cbc:Amount currencyID="KWD">-.050</cbc:Amount></cac:AllowanceCharge></CreditNote>`, 1)
	v, err = ParseXML(t.Context(), []byte(credit))
	if err != nil || len(v.Allowances) != 1 || v.Allowances[0].Charge || v.Allowances[0].Amount != "-0.050" {
		t.Fatalf("UBL allowance lexical forms: %+v %v", v, err)
	}
}

func TestXMLRejectsUntrustedOrAmbiguousData(t *testing.T) {
	for name, data := range map[string][]byte{
		"DTD": []byte(`<!DOCTYPE x [<!ENTITY a SYSTEM "file:///etc/passwd">]><x/>`), "wrong namespace": bytes.ReplaceAll(fixtures.CII, []byte("CrossIndustryInvoice:100"), []byte("fake:100")), "missing currency": bytes.ReplaceAll(fixtures.CII, []byte(">EUR<"), []byte("><")), "invented currency": bytes.ReplaceAll(fixtures.CII, []byte("EUR"), []byte("ZZZ")), "exponent": bytes.ReplaceAll(fixtures.CII, []byte("119.00"), []byte("1.19e2")), "trailing root": append(append([]byte{}, fixtures.CII...), []byte("<x/>")...), "deep": []byte(strings.Repeat("<x>", 65) + strings.Repeat("</x>", 65)), "oversized": bytes.Repeat([]byte("x"), (2<<20)+1),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseXML(t.Context(), data); err == nil {
				t.Fatal("unsafe XML accepted")
			}
		})
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := ParseXML(ctx, fixtures.CII); err == nil {
		t.Fatal("ignored cancellation")
	}
}
