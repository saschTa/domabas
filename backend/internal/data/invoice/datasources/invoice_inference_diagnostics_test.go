package datasources

import (
	"bytes"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"testing"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

func TestInvoiceRejectionDiagnosticsExcludePrivateValues(t *testing.T) {
	for _, scenario := range []struct{ name, response, reason string }{
		{"invalid envelope", `{"private":"SECRET_RESPONSE"}`, "invalid_envelope"},
		{"null invoice", `{"invoice":null}`, "missing_invoice"},
		{"unexpected decision", `{"isInvoice":false,"invoice":null}`, "invalid_envelope"},
		{"invalid payload", `{"invoice":{"number":123}}`, "invalid_payload"},
		{"invalid fields", strings.Replace(invoiceSchemaTestResponse, `"vatAccounting":null`, `"vatAccounting":null,"dueDate":"SECRET_FIELD"`, 1), "invalid_fields"},
		{"unsupported source", invoiceSchemaTestResponse, "unsupported_source_evidence"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var logs bytes.Buffer
			logger := slog.New(slog.NewJSONHandler(&logs, nil))
			inference := &inferenceFixture{response: scenario.response}
			_, err := NewInvoiceExtractorDataSource(inference, logger).InferClassified(t.Context(), document.DocumentLLMConfiguration{Model: "fixture-model"}, "SECRET_KEY", "SECRET_DOCUMENT 123 EUR")
			var failure document.DocumentProcessingError
			if !errors.As(err, &failure) || failure.Code != "invalid_invoice" || failure.Retryable {
				t.Fatalf("public failure changed: %v", err)
			}
			var record map[string]any
			if json.Unmarshal(logs.Bytes(), &record) != nil || record["msg"] != "ai_invoice_validation" || record["reason"] != scenario.reason || record["task"] != "invoice_extraction" || record["model"] != "fixture-model" {
				t.Fatalf("missing rejection diagnostic: %s", logs.String())
			}
			if strings.Contains(logs.String(), "SECRET") {
				t.Fatal("private content leaked into logs")
			}
		})
	}
}

func TestInvoiceClassifierRejectionDiagnostic(t *testing.T) {
	var logs bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logs, nil))
	inference := &inferenceFixture{response: `{"reason":"SECRET_RESPONSE"}`}
	_, err := NewInvoiceClassifierDataSource(inference, logger).Classify(t.Context(), document.DocumentLLMConfiguration{Model: "fixture-model"}, "SECRET_KEY", invoice.SelectInvoiceClassificationInput("SECRET_DOCUMENT", 1))
	var failure document.DocumentProcessingError
	if !errors.As(err, &failure) || failure.Code != "invalid_classification" {
		t.Fatalf("unexpected error: %v", err)
	}
	var record map[string]any
	if json.Unmarshal(logs.Bytes(), &record) != nil || record["task"] != "invoice_classification" || record["reason"] != "invalid_reason" || strings.Contains(logs.String(), "SECRET") {
		t.Fatalf("unsafe or missing diagnostic: %s", logs.String())
	}
}
