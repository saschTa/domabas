package services

import (
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestLMStudioCompatibilityUpdatesOnlyAIAndPreservesOmission(t *testing.T) {
	service := &DocumentIngestionService{}
	current := m.DefaultConfiguration()
	current.LLM.Provider, current.LLM.BaseURL = "openai", "http://model.test/v1"
	current.Fingerprint, _ = current.CanonicalFingerprint()
	update := m.DocumentLLMConfigurationUpdate{Provider: current.LLM.Provider, Model: current.LLM.Model, BaseURL: current.LLM.BaseURL, LMStudioCompatibility: new(true)}
	for _, choice := range []*bool{new(true), nil, new(false)} {
		update.LMStudioCompatibility = choice
		input := m.DocumentProcessingConfiguration{Language: current.Language, Segmentation: current.Segmentation, LLMUpdate: &update}
		change, err := service.configurationChange(t.Context(), current, input)
		if err != nil || change.Reindex || change.RescheduleAI != (choice != nil) {
			t.Fatalf("wrong settings transition: %+v %v", change, err)
		}
		want := current.LLM.LMStudioCompatibility
		if choice != nil {
			want = *choice
		}
		if change.Configuration.LLM.LMStudioCompatibility != want || (change.Configuration.Fingerprint == current.Fingerprint) != (choice == nil) {
			t.Fatal("compatibility or fingerprint was not preserved")
		}
		current = change.Configuration
	}
}
