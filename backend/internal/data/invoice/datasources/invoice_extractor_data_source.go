package datasources

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"strings"

	r "github.com/domabas/domabas/backend/internal/data/invoice/models"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

type InvoiceInference interface {
	Generate(context.Context, string, string, string, string, string, string, string, int, float64, bool, bool, ...int) (string, error)
}
type InvoiceExtractorDataSource struct {
	inference InvoiceInference
	logger    *slog.Logger
}

func NewInvoiceExtractorDataSource(inference InvoiceInference, loggers ...*slog.Logger) *InvoiceExtractorDataSource {
	var logger *slog.Logger
	if len(loggers) > 0 {
		logger = loggers[0]
	}
	return &InvoiceExtractorDataSource{inference: inference, logger: logger}
}
func (e *InvoiceExtractorDataSource) Structured(ctx context.Context, data []byte) (*m.Invoice, error) {
	return ParseXML(ctx, data)
}

func (e *InvoiceExtractorDataSource) Infer(ctx context.Context, c document.DocumentLLMConfiguration, key, text string) (*m.Invoice, error) {
	return e.infer(ctx, c, key, text, false)
}

func (e *InvoiceExtractorDataSource) InferClassified(ctx context.Context, c document.DocumentLLMConfiguration, key, text string) (*m.Invoice, error) {
	return e.infer(ctx, c, key, text, true)
}

func (e *InvoiceExtractorDataSource) infer(ctx context.Context, c document.DocumentLLMConfiguration, key, text string, classified bool) (*m.Invoice, error) {
	prefix := m.InvoiceSourcePrefix(text)
	text = prefix
	prompt, schema := m.InvoiceClassificationPrompt, invoiceSchema
	if classified {
		prompt = m.InvoiceExtractionPrompt
		schema = invoiceExtractionSchema
	}
	content, err := e.inference.Generate(ctx, c.Provider, c.Model, c.BaseURL, key, prompt, schema, text, 50000, 0.2, c.LMStudioCompatibility, c.InvoiceThinkingEnabled, c.RequestedContextLength())
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(strings.NewReader(content))
	decoder.DisallowUnknownFields()
	var response struct {
		Invoice json.RawMessage
	}
	if classified {
		if decoder.Decode(&response) != nil || decoder.Decode(new(any)) != io.EOF {
			return nil, e.inferenceFailure(ctx, c.Model, "invalid_envelope")
		}
	} else {
		var legacy struct {
			IsInvoice *bool
			Invoice   json.RawMessage
		}
		if decoder.Decode(&legacy) != nil || decoder.Decode(new(any)) != io.EOF || legacy.IsInvoice == nil {
			return nil, e.inferenceFailure(ctx, c.Model, "invalid_envelope")
		}
		if !*legacy.IsInvoice {
			return nil, nil
		}
		response.Invoice = legacy.Invoice
	}
	var payload *r.InferredInvoice
	invoiceDecoder := json.NewDecoder(bytes.NewReader(response.Invoice))
	invoiceDecoder.DisallowUnknownFields()
	if invoiceDecoder.Decode(&payload) != nil {
		return nil, e.inferenceFailure(ctx, c.Model, "invalid_payload")
	}
	if payload == nil {
		return nil, e.inferenceFailure(ctx, c.Model, "missing_invoice")
	}
	v := &m.Invoice{Source: "ai", Format: "ai", ExtractionModel: c.Model, Number: payload.Number, TypeCode: payload.TypeCode, IssueDate: payload.IssueDate, DueDate: payload.DueDate, Currency: payload.Currency, TotalNet: payload.TotalNet, TotalTax: payload.TotalTax, TotalGross: payload.TotalGross, AmountDue: payload.AmountDue, PaidAmount: payload.PaidAmount, RoundingAmount: payload.RoundingAmount, Seller: m.InvoiceParty(payload.Seller), Buyer: m.InvoiceParty(payload.Buyer), Payment: m.InvoicePayment(payload.Payment), Notes: payload.Notes}
	if tax := payload.VATAccounting; tax != nil {
		v.TaxCurrency, v.TaxAccountingAmount = tax.Currency, tax.Amount
		if tax.Currency == "" && tax.Amount == "" {
			return nil, e.inferenceFailure(ctx, c.Model, "invalid_accounting_tax")
		}
	}
	for _, line := range payload.Lines {
		v.Lines = append(v.Lines, m.InvoiceLine(line))
	}
	for _, tax := range payload.Taxes {
		v.Taxes = append(v.Taxes, m.InvoiceTax(tax))
	}
	for _, allowance := range payload.Allowances {
		v.Allowances = append(v.Allowances, m.InvoiceAllowance(allowance))
	}
	for _, reference := range payload.References {
		v.References = append(v.References, m.InvoiceReference{Number: reference.Number, IssueDate: reference.IssueDate})
	}
	if err = validateInvoice(*v); err != nil {
		return nil, e.inferenceFailure(ctx, c.Model, "invalid_fields")
	}
	accepted, err := (m.InvoiceEvidencePolicy{}).Accept(text, *v)
	if err != nil || !accepted {
		return nil, e.inferenceFailure(ctx, c.Model, "unsupported_source_evidence")
	}
	return v, nil
}

func (e *InvoiceExtractorDataSource) inferenceFailure(ctx context.Context, model, reason string) error {
	return invoiceInferenceFailure(ctx, e.logger, model, "invoice_extraction", reason, "invalid_invoice")
}
