package repos

import (
	"context"
	"testing"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type propertyCompatibilitySource struct {
	compatibility bool
	thinking      bool
}

func (s *propertyCompatibilitySource) Extract(_ context.Context, _, _, _, _, _ string, compatibility, thinking bool, _ ...int) (r.DocumentExtractedProperties, error) {
	s.compatibility = compatibility
	s.thinking = thinking
	return r.DocumentExtractedProperties{Subject: "Synthetic subject"}, nil
}

func TestPropertyExtractionUsesAcceptedCompatibilitySetting(t *testing.T) {
	for _, compatible := range []bool{false, true} {
		source := &propertyCompatibilitySource{}
		repository := NewDocumentPropertyExtractionRepository(source)
		result, err := repository.ExtractProperties(t.Context(), m.DocumentLLMConfiguration{Provider: "openai", LMStudioCompatibility: compatible}, "", "Synthetic document")
		if err != nil || source.compatibility != compatible || result.Subject != "Synthetic subject" {
			t.Fatalf("accepted compatibility lost: %+v %v", source, err)
		}
	}
}

func TestPropertyThinkingIsIndependentFromInvoiceThinking(t *testing.T) {
	for _, thinking := range []bool{false, true} {
		source := &propertyCompatibilitySource{}
		repository := NewDocumentPropertyExtractionRepository(source)
		_, err := repository.ExtractProperties(t.Context(), m.DocumentLLMConfiguration{PropertyThinkingEnabled: thinking, InvoiceThinkingEnabled: !thinking}, "", "Synthetic document")
		if err != nil || source.thinking != thinking {
			t.Fatalf("property thinking lost: %+v %v", source, err)
		}
	}
}
