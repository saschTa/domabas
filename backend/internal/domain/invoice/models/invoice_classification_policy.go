package models

import (
	"fmt"
	"slices"
	"strings"
	"unicode"
)

func NewInvoiceClassification(reason string, input InvoiceClassificationInput) (InvoiceClassification, error) {
	result := InvoiceClassification{Reason: reason, InputCharacters: input.InputCharacters, SourceCharacters: input.SourceCharacters, Pass: input.Pass}
	switch reason {
	case "invoice", "credit_note":
		result.Decision = "invoice"
	case "quotation", "order", "delivery_note", "bank_statement", "forwarding_email", "other_document":
		result.Decision = "not_invoice"
	case "insufficient_text", "mixed_document", "ambiguous":
		result.Decision = "uncertain"
	default:
		return result, ErrInvalid
	}
	return result, result.Validate()
}

func SelectInvoiceClassificationInput(text string, pass int) InvoiceClassificationInput {
	runes := []rune(text)
	budget := 20000
	if pass == 2 {
		budget = 50000
	}
	input := InvoiceClassificationInput{SourceCharacters: len(runes), Pass: pass}
	if len(runes) <= budget {
		input.Text = text
		input.InputCharacters = len(runes)
		return input
	}
	var parts []string
	for i := range 4 {
		size := budget / 4
		start := (len(runes) - size) * i / 3
		parts = append(parts, fmt.Sprintf("[Source characters %d-%d]\n%s", start, start+size, string(runes[start:start+size])))
		input.InputCharacters += size
	}
	input.Text = strings.Join(parts, "\n[Omitted text]\n")
	return input
}

func InvoiceClassificationTextUsable(text string) bool {
	letters := 0
	for _, r := range text {
		if unicode.IsLetter(r) {
			letters++
		}
	}
	return letters >= 20
}

func (c InvoiceClassification) Validate() error {
	if c.Pass < 1 || c.Pass > 2 || c.InputCharacters < 0 || c.SourceCharacters < c.InputCharacters {
		return ErrInvalid
	}
	switch c.Decision {
	case "invoice":
		if !slices.Contains([]string{"invoice", "credit_note"}, c.Reason) {
			return ErrInvalid
		}
	case "not_invoice":
		if !slices.Contains([]string{"quotation", "order", "delivery_note", "bank_statement", "forwarding_email", "other_document"}, c.Reason) {
			return ErrInvalid
		}
	case "uncertain":
		if !slices.Contains([]string{"insufficient_text", "mixed_document", "ambiguous", "incomplete_coverage", "prior_invoice"}, c.Reason) {
			return ErrInvalid
		}
	default:
		return ErrInvalid
	}
	return nil
}

func FinalizeInvoiceClassification(c InvoiceClassification, existingSource string) InvoiceClassification {
	if c.Decision == "not_invoice" && c.InputCharacters < c.SourceCharacters {
		c.Decision, c.Reason = "uncertain", "incomplete_coverage"
	}
	if c.Decision == "not_invoice" && existingSource != "" {
		c.Decision, c.Reason = "uncertain", "prior_invoice"
	}
	return c
}

func InvoiceClassificationNeedsWiderInput(c InvoiceClassification) bool {
	return c.Pass == 1 && c.Decision != "invoice" && c.Reason != "prior_invoice" && c.InputCharacters < c.SourceCharacters
}
