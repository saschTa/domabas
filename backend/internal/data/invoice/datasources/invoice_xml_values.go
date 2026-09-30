package datasources

import (
	"regexp"
	"strings"

	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

var xmlDecimal = regexp.MustCompile(`^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$`)

func xmlTrue(value string) bool { return value == "true" || value == "1" }

func normalizedXMLDecimal(value string) string {
	if !xmlDecimal.MatchString(value) {
		return value
	}
	sign := ""
	if strings.HasPrefix(value, "-") {
		sign = "-"
	}
	value = strings.TrimPrefix(strings.TrimPrefix(value, "-"), "+")
	integer, fraction, _ := strings.Cut(value, ".")
	integer = strings.TrimLeft(integer, "0")
	if integer == "" {
		integer = "0"
	}
	if fraction != "" {
		return sign + integer + "." + fraction
	}
	return sign + integer
}

func normalizeXMLDecimals(v *m.Invoice) {
	values := []*string{&v.TotalNet, &v.TotalTax, &v.TotalGross, &v.AmountDue, &v.PaidAmount, &v.RoundingAmount, &v.TaxAccountingAmount}
	for i := range v.Lines {
		l := &v.Lines[i]
		values = append(values, &l.Quantity, &l.UnitPrice, &l.NetAmount, &l.TaxRate)
	}
	for i := range v.Taxes {
		t := &v.Taxes[i]
		values = append(values, &t.Rate, &t.TaxableAmount, &t.TaxAmount)
	}
	for i := range v.Allowances {
		a := &v.Allowances[i]
		values = append(values, &a.Amount, &a.TaxRate)
	}
	for _, value := range values {
		*value = normalizedXMLDecimal(*value)
	}
}
