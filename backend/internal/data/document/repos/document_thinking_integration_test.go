//go:build integration

package repos_test

import (
	"encoding/json"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"testing"
)

func TestThinkingSettingsPersistIndependentlyAndKeepAcceptedSnapshots(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	ctx := t.Context()
	previous, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil || previous.LLM.PropertyThinkingEnabled || previous.LLM.InvoiceThinkingEnabled {
		t.Fatal("thinking must default off", err)
	}
	current := previous
	for _, step := range []struct {
		properties, invoices                  *bool
		wantProperties, wantInvoices, changed bool
	}{
		{new(true), nil, true, false, true},
		{nil, new(true), true, true, true},
		{nil, nil, true, true, false},
		{new(false), nil, false, true, true},
		{nil, new(false), false, false, true},
	} {
		update := m.DocumentLLMConfigurationUpdate{Provider: current.LLM.Defaults().Provider, Model: current.LLM.Model, PropertyThinkingEnabled: step.properties, InvoiceThinkingEnabled: step.invoices}
		input := m.DocumentProcessingConfiguration{Language: current.Language, Segmentation: current.Segmentation, ExpectedRevision: &current.Revision, LLMUpdate: &update}
		saved, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
		wantRevision := current.Revision
		if step.changed {
			wantRevision++
		}
		if err != nil || saved.Revision != wantRevision || saved.AutomaticBatchID != "" || saved.LLM.PropertyThinkingEnabled != step.wantProperties || saved.LLM.InvoiceThinkingEnabled != step.wantInvoices {
			t.Fatalf("thinking save: %+v %v", saved, err)
		}
		var propertyThinking, invoiceThinking bool
		var reschedule int64
		if err := f.connection.QueryRow(ctx, `SELECT llm_property_thinking_enabled,llm_invoice_thinking_enabled,ai_reschedule_revision FROM document_processing_configuration WHERE id`).Scan(&propertyThinking, &invoiceThinking, &reschedule); err != nil || propertyThinking != step.wantProperties || invoiceThinking != step.wantInvoices || reschedule != saved.Revision {
			t.Fatalf("typed settings or AI-only schedule lost: %t %t %d %v", propertyThinking, invoiceThinking, reschedule, err)
		}
		if err := initializeDocumentSource(ctx, source); err != nil {
			t.Fatal(err)
		}
		restarted, err := f.service.GetProcessingConfiguration(ctx, f.actor)
		if err != nil || !restarted.LLM.Equal(saved.LLM) || restarted.Revision != saved.Revision {
			t.Fatal("thinking did not survive restart", err)
		}
		var encoded []byte
		if err := f.connection.QueryRow(ctx, `SELECT configuration FROM document_processing_configurations WHERE revision=$1`, current.Revision).Scan(&encoded); err != nil {
			t.Fatal(err)
		}
		var retained m.DocumentProcessingConfiguration
		if err := json.Unmarshal(encoded, &retained); err != nil || !retained.LLM.Equal(current.LLM) || retained.Fingerprint != current.Fingerprint {
			t.Fatal("retained settings changed", err)
		}
		current = saved
	}
}

func TestThinkingFingerprintMatchesSQL(t *testing.T) {
	f := newIngestionFixture(t)
	for _, propertyThinking := range []bool{false, true} {
		for _, invoiceThinking := range []bool{false, true} {
			for _, compatibility := range []bool{false, true} {
				for _, current := range []bool{false, true} {
					c := m.DefaultConfiguration()
					if !current {
						c.LLM = m.DocumentLLMConfiguration{}
					}
					c.LLM.PropertyThinkingEnabled, c.LLM.InvoiceThinkingEnabled, c.LLM.LMStudioCompatibility = propertyThinking, invoiceThinking, compatibility
					want, err := c.CanonicalFingerprint()
					if err != nil {
						t.Fatal(err)
					}
					encoded, _ := json.Marshal(c)
					var got string
					if err := f.connection.QueryRow(t.Context(), `SELECT document_pipeline_fingerprint($1::jsonb)`, encoded).Scan(&got); err != nil || got != want {
						t.Fatalf("SQL thinking fingerprint differs: %+v %s %s %v", c.LLM, got, want, err)
					}
				}
			}
		}
	}
}
