package datasources

import (
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"golang.org/x/text/currency"
)

func validateInvoice(v m.Invoice) error {
	_, currencyErr := currency.ParseISO(v.Currency)
	_, taxCurrencyErr := currency.ParseISO(v.TaxCurrency)
	return v.ValidateCurrencyFacts(currencyErr == nil, taxCurrencyErr == nil)
}
