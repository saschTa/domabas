package datasources

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"strings"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

const invoiceDetectionSchema = `{"type":"object","additionalProperties":false,"required":["reason"],"properties":{"reason":{"type":"string","enum":["invoice","credit_note","quotation","order","delivery_note","bank_statement","forwarding_email","other_document","insufficient_text","mixed_document","ambiguous"]}}}`

type InvoiceClassifierDataSource struct {
	inference InvoiceInference
	logger    *slog.Logger
}

func NewInvoiceClassifierDataSource(inference InvoiceInference, loggers ...*slog.Logger) *InvoiceClassifierDataSource {
	var logger *slog.Logger
	if len(loggers) > 0 {
		logger = loggers[0]
	}
	return &InvoiceClassifierDataSource{inference: inference, logger: logger}
}

func (s *InvoiceClassifierDataSource) Classify(ctx context.Context, c document.DocumentLLMConfiguration, key string, input m.InvoiceClassificationInput) (m.InvoiceClassification, error) {
	result := m.InvoiceClassification{InputCharacters: input.InputCharacters, SourceCharacters: input.SourceCharacters, Pass: input.Pass}
	prompt := m.InvoiceDetectionPrompt + fmt.Sprintf("\nSupplied %d of %d source characters. Classification pass %d.", input.InputCharacters, input.SourceCharacters, input.Pass)
	content, err := s.inference.Generate(ctx, c.Provider, c.Model, c.BaseURL, key, prompt, invoiceDetectionSchema, input.Text, 256, 0.2, c.LMStudioCompatibility, c.InvoiceThinkingEnabled, c.RequestedContextLength())
	if err != nil {
		return result, err
	}
	decoder := json.NewDecoder(strings.NewReader(content))
	start, err := decoder.Token()
	if err != nil || start != json.Delim('{') {
		return result, invoiceInferenceFailure(ctx, s.logger, c.Model, "invoice_classification", "invalid_json", "invalid_classification")
	}
	fields := make(map[string]string, 1)
	for decoder.More() {
		token, err := decoder.Token()
		name, ok := token.(string)
		_, duplicate := fields[name]
		var value string
		if err != nil || !ok || duplicate || name != "reason" || decoder.Decode(&value) != nil {
			return result, invoiceInferenceFailure(ctx, s.logger, c.Model, "invoice_classification", "invalid_fields", "invalid_classification")
		}
		fields[name] = value
	}
	end, err := decoder.Token()
	if err != nil || end != json.Delim('}') || decoder.Decode(new(any)) != io.EOF {
		return result, invoiceInferenceFailure(ctx, s.logger, c.Model, "invoice_classification", "invalid_json", "invalid_classification")
	}
	result, err = m.NewInvoiceClassification(fields["reason"], input)
	if err != nil {
		return result, invoiceInferenceFailure(ctx, s.logger, c.Model, "invoice_classification", "invalid_reason", "invalid_classification")
	}
	return result, nil
}
