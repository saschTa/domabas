//go:build integration

package repos_test

import (
	"encoding/json"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestLMStudioCompatibilityPersistsWithoutChangingRetainedSettings(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	ctx := t.Context()
	previous, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil || previous.LLM.LMStudioCompatibility {
		t.Fatal("compatibility must default off", err)
	}
	update := m.DocumentLLMConfigurationUpdate{Provider: "openai", Model: "fixture", BaseURL: "http://model.test/v1", LMStudioCompatibility: new(true)}
	input := m.DocumentProcessingConfiguration{Language: previous.Language, Segmentation: previous.Segmentation, ExpectedRevision: &previous.Revision, LLMUpdate: &update}
	saved, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil || !saved.LLM.LMStudioCompatibility || saved.AutomaticBatchID != "" || saved.Revision != previous.Revision+1 {
		t.Fatalf("compatibility update: %+v %v", saved, err)
	}
	var active bool
	var reschedule int64
	if err := f.connection.QueryRow(ctx, `SELECT llm_lm_studio_compatibility,ai_reschedule_revision FROM document_processing_configuration WHERE id`).Scan(&active, &reschedule); err != nil || !active || reschedule != saved.Revision {
		t.Fatalf("typed setting or AI scheduling lost: %t %d %v", active, reschedule, err)
	}
	if err := initializeDocumentSource(ctx, source); err != nil {
		t.Fatal(err)
	}
	restarted, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil || !restarted.LLM.LMStudioCompatibility || restarted.Revision != saved.Revision {
		t.Fatal("compatibility did not survive restart", err)
	}
	update.LMStudioCompatibility = nil
	input.ExpectedRevision = &saved.Revision
	unchanged, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil || !unchanged.LLM.LMStudioCompatibility || unchanged.Revision != saved.Revision {
		t.Fatal("omitted compatibility overwrote saved choice", err)
	}
	var encoded []byte
	if err := f.connection.QueryRow(ctx, `SELECT configuration FROM document_processing_configurations WHERE revision=$1`, previous.Revision).Scan(&encoded); err != nil {
		t.Fatal(err)
	}
	var retained m.DocumentProcessingConfiguration
	if err := json.Unmarshal(encoded, &retained); err != nil || retained.LLM.LMStudioCompatibility || retained.Fingerprint != previous.Fingerprint {
		t.Fatal("retained configuration was changed", err)
	}
	update.LMStudioCompatibility = new(false)
	disabled, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil || disabled.LLM.LMStudioCompatibility || disabled.Revision != saved.Revision+1 {
		t.Fatal("explicit false did not disable compatibility", err)
	}
}

func TestLMStudioFingerprintMatchesSQL(t *testing.T) {
	f := newIngestionFixture(t)
	for _, compatibility := range []bool{false, true} {
		for _, external := range []bool{false, true} {
			for _, contextLength := range []int{0, 32768} {
				configuration := m.DefaultConfiguration()
				configuration.LLM = m.DocumentLLMConfiguration{LMStudioCompatibility: compatibility, ContextLength: contextLength}
				if external {
					configuration.LLM.Provider, configuration.LLM.Model, configuration.LLM.BaseURL = "openai", "fixture", "http://model.test/v1"
				}
				want, err := configuration.CanonicalFingerprint()
				if err != nil {
					t.Fatal(err)
				}
				encoded, _ := json.Marshal(configuration)
				var got string
				if err := f.connection.QueryRow(t.Context(), `SELECT document_pipeline_fingerprint($1::jsonb)`, encoded).Scan(&got); err != nil || got != want {
					t.Fatalf("SQL compatibility fingerprint mismatch: %+v %s %s %v", configuration.LLM, got, want, err)
				}
			}
		}
	}
}
