package models

import (
	"errors"
	"math/big"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

var ErrInvalid = errors.New("invalid invoice")
var ErrNotFound = errors.New("invoice not found")
var ErrForbidden = errors.New("invoice permission denied")
var decimal = regexp.MustCompile(`^-?(0|[1-9][0-9]{0,23})(\.[0-9]{1,12})?$`)

func Decimal(value string) bool { return value == "" || decimal.MatchString(value) }
func date(value string) bool {
	if value == "" {
		return true
	}
	_, err := time.Parse("2006-01-02", value)
	return err == nil
}
func validCurrency(value string) bool {
	if len(value) != 3 || value != strings.ToUpper(value) || value == "XXX" {
		return false
	}
	for _, c := range value {
		if c < 'A' || c > 'Z' {
			return false
		}
	}
	return true
}
func (v Invoice) Validate() error {
	if v.Source != "structured" && v.Source != "ai" {
		return ErrInvalid
	}
	if v.Number == "" || v.Seller.Name == "" || !validCurrency(v.Currency) || (v.TaxCurrency != "" && !validCurrency(v.TaxCurrency)) || !date(v.IssueDate) || !date(v.DueDate) {
		return ErrInvalid
	}
	if v.TaxAccountingAmount != "" && v.TaxCurrency == "" {
		return ErrInvalid
	}
	if v.Source == "ai" && (v.TaxCurrency != "" || v.TaxAccountingAmount != "") && (v.TaxCurrency == "" || v.TaxAccountingAmount == "" || v.TaxCurrency == v.Currency) {
		return ErrInvalid
	}
	if len(v.Lines) > 200 || len(v.Taxes) > 50 || len(v.Allowances) > 100 || len(v.References) > 50 || len(v.Notes) > 50 {
		return ErrInvalid
	}
	texts := []string{v.Number, v.TypeCode, v.Profile, v.ExtractionModel}
	for _, p := range []InvoiceParty{v.Seller, v.Buyer} {
		texts = append(texts, p.Name, p.TaxID, p.RegistrationID, p.Address, p.Country, p.Email)
	}
	amounts := []string{v.TotalNet, v.TotalTax, v.TotalGross, v.AmountDue, v.PaidAmount, v.RoundingAmount, v.TaxAccountingAmount}
	for _, l := range v.Lines {
		texts = append(texts, l.ID, l.Description, l.UnitCode, l.TaxCategory)
		amounts = append(amounts, l.Quantity, l.UnitPrice, l.NetAmount, l.TaxRate)
	}
	for _, t := range v.Taxes {
		texts = append(texts, t.Category, t.ExemptionReason)
		amounts = append(amounts, t.Rate, t.TaxableAmount, t.TaxAmount)
	}
	for _, a := range v.Allowances {
		texts = append(texts, a.Reason, a.TaxCategory)
		amounts = append(amounts, a.Amount, a.TaxRate)
	}
	for _, r := range v.References {
		if !date(r.IssueDate) || r.Number == "" {
			return ErrInvalid
		}
		texts = append(texts, r.Number)
	}
	texts = append(texts, v.Payment.MeansCode, v.Payment.Reference, v.Payment.IBAN, v.Payment.BIC, v.Payment.Terms)
	texts = append(texts, v.Notes...)
	for _, s := range texts {
		if !utf8.ValidString(s) || strings.ContainsRune(s, 0) || utf8.RuneCountInString(s) > 4000 {
			return ErrInvalid
		}
	}
	for _, s := range amounts {
		if !Decimal(s) {
			return ErrInvalid
		}
	}
	return nil
}

func (v Invoice) ValidateCurrencyFacts(currencyKnown, taxCurrencyKnown bool) error {
	if !currencyKnown || v.TaxCurrency != "" && !taxCurrencyKnown {
		return ErrInvalid
	}
	return v.Validate()
}
func (q InvoiceQuery) Validate() error {
	if q.Limit < 1 || q.Limit > 50 || len(q.Cursor) > 32768 || (q.Source != "" && q.Source != "structured" && q.Source != "ai") || !utf8.ValidString(q.Text) || len(q.Text) > 800 || utf8.RuneCountInString(q.Text) > 200 || strings.ContainsRune(q.Text, 0) {
		return ErrInvalid
	}
	switch q.Sort {
	case "", "created_desc", "created_asc", "due_asc", "due_desc", "issue_asc", "issue_desc", "number_asc", "number_desc", "seller_asc", "seller_desc", "buyer_asc", "buyer_desc":
	default:
		return ErrInvalid
	}
	for _, value := range []string{q.Number, q.Seller, q.Buyer, q.Currency, q.TypeCode, q.Format, q.PaymentMeansCode} {
		if !validInvoiceFilterValue(value) {
			return ErrInvalid
		}
	}
	for _, bounds := range [][2]string{{q.CreatedFrom, q.CreatedTo}, {q.IssueFrom, q.IssueTo}, {q.DueFrom, q.DueTo}} {
		if strings.HasPrefix(bounds[0], "0000-") || strings.HasPrefix(bounds[1], "0000-") || !date(bounds[0]) || !date(bounds[1]) || (bounds[0] != "" && bounds[1] != "" && bounds[0] > bounds[1]) {
			return ErrInvalid
		}
	}
	if !Decimal(q.TotalMin) || !Decimal(q.TotalMax) || ((q.TotalMin != "" || q.TotalMax != "") && !validCurrency(q.Currency)) {
		return ErrInvalid
	}
	if q.TotalMin != "" && q.TotalMax != "" {
		minimum, _ := new(big.Rat).SetString(q.TotalMin)
		maximum, _ := new(big.Rat).SetString(q.TotalMax)
		if minimum.Cmp(maximum) > 0 {
			return ErrInvalid
		}
	}

	return nil
}

func validInvoiceFilterValue(value string) bool {
	return utf8.ValidString(value) && !strings.ContainsRune(value, 0) && utf8.RuneCountInString(value) <= 4000
}
func (q InvoiceFilterValueQuery) Validate() error {
	if err := (InvoiceQuery{Limit: q.Limit, Cursor: q.Cursor, Text: q.Text}).Validate(); err != nil {
		return err
	}
	switch q.Field {
	case "number", "seller", "buyer", "currency", "typeCode", "format", "paymentMeansCode":
		return nil
	default:
		return ErrInvalid
	}
}
