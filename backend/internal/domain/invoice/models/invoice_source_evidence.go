package models

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

func InvoiceSourcePrefix(text string) string {
	runes := []rune(text)
	return string(runes[:min(len(runes), 100000)])
}

func (p InvoiceEvidencePolicy) Accept(text string, v Invoice) (bool, error) {
	source := strings.ToLower(strings.Join(strings.Fields(text), " "))
	identifiers := []string{v.Number}
	dates := []string{v.IssueDate, v.DueDate}
	numbers := []string{v.TotalNet, v.TotalTax, v.TotalGross, v.AmountDue, v.PaidAmount, v.RoundingAmount, v.TaxAccountingAmount}
	for _, line := range v.Lines {
		identifiers = append(identifiers, line.ID)
		numbers = append(numbers, line.Quantity, line.UnitPrice, line.NetAmount, line.TaxRate)
	}
	for _, tax := range v.Taxes {
		numbers = append(numbers, tax.Rate, tax.TaxableAmount, tax.TaxAmount)
	}
	for _, allowance := range v.Allowances {
		numbers = append(numbers, allowance.Amount, allowance.TaxRate)
	}
	for _, reference := range v.References {
		identifiers = append(identifiers, reference.Number)
		dates = append(dates, reference.IssueDate)
	}
	for _, value := range identifiers {
		value = strings.ToLower(strings.Join(strings.Fields(value), " "))
		if value != "" && !invoiceContainsToken(source, value) {
			return false, ErrInvalid
		}
	}
	printedNumbers := invoiceSourceNumbers(text)
	for _, value := range numbers {
		if value != "" && !printedNumbers[invoiceCanonicalDecimal(value)] {
			return false, ErrInvalid
		}
	}
	printedDates := invoiceSourceDates(text)
	for _, value := range dates {
		if value != "" && !printedDates[value] {
			return false, ErrInvalid
		}
	}
	return true, nil
}

func invoiceContainsToken(text, value string) bool {
	if value == "" {
		return false
	}
	for offset := 0; offset <= len(text); {
		found := strings.Index(text[offset:], value)
		if found < 0 {
			return false
		}
		start := offset + found
		if invoiceTokenBoundary(text, start, start+len(value)) {
			return true
		}
		offset = start + len(value)
	}
	return false
}

func invoiceTokenBoundary(text string, start, end int) bool {
	word := func(r rune) bool {
		return unicode.IsLetter(r) || unicode.IsDigit(r) || strings.ContainsRune("_+-−/", r)
	}
	if start > 0 {
		r, size := utf8.DecodeLastRuneInString(text[:start])
		if word(r) {
			return false
		}
		if strings.ContainsRune(".,'’", r) && start > size {
			before, _ := utf8.DecodeLastRuneInString(text[:start-size])
			if unicode.IsLetter(before) || unicode.IsDigit(before) {
				return false
			}
		}
	}
	if end < len(text) {
		r, size := utf8.DecodeRuneInString(text[end:])
		if word(r) {
			return false
		}
		if strings.ContainsRune(".,'’", r) && end+size < len(text) {
			after, _ := utf8.DecodeRuneInString(text[end+size:])
			if unicode.IsLetter(after) || unicode.IsDigit(after) {
				return false
			}
		}
	}
	return true
}
