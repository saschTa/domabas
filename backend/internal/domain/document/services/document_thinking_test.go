package services

import (
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"testing"
)

func TestThinkingChangesOnlyAIAndPreservesOmittedChoices(t *testing.T) {
	service := &DocumentIngestionService{}
	current := m.DefaultConfiguration()
	current.LLM = current.LLM.Defaults()
	current.Fingerprint, _ = current.CanonicalFingerprint()
	for _, step := range []struct {
		properties, invoices                  *bool
		wantProperties, wantInvoices, changed bool
	}{
		{new(true), nil, true, false, true},
		{nil, new(true), true, true, true},
		{nil, nil, true, true, false},
		{new(false), nil, false, true, true},
		{nil, new(false), false, false, true},
		{new(false), new(false), false, false, false},
	} {
		update := m.DocumentLLMConfigurationUpdate{Provider: current.LLM.Provider, Model: current.LLM.Model, PropertyThinkingEnabled: step.properties, InvoiceThinkingEnabled: step.invoices}
		change, err := service.configurationChange(t.Context(), current, m.DocumentProcessingConfiguration{Language: current.Language, Segmentation: current.Segmentation, LLMUpdate: &update})
		if err != nil || change.Reindex || change.RescheduleAI != step.changed || change.Configuration.LLM.PropertyThinkingEnabled != step.wantProperties || change.Configuration.LLM.InvoiceThinkingEnabled != step.wantInvoices {
			t.Fatalf("wrong thinking transition: %+v %v", change, err)
		}
		if (change.Configuration.Fingerprint != current.Fingerprint) != step.changed {
			t.Fatal("thinking change lost settings identity")
		}
		current = change.Configuration
	}
}
