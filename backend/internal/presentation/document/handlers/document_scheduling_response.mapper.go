package handlers

import (
	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

func documentSchedulingResponseMapper(value *domain.DocumentProcessingScheduling) *contract.DocumentProcessingScheduling {
	if value == nil {
		return nil
	}
	return &contract.DocumentProcessingScheduling{IngestionConcurrency: value.IngestionConcurrency, AiConcurrency: value.AIConcurrency, OllamaQueueSize: value.OllamaQueueSize, IngestionConcurrencyMode: contract.DocumentProcessingSchedulingIngestionConcurrencyMode(value.IngestionConcurrencyMode), AiConcurrencyMode: contract.DocumentProcessingSchedulingAiConcurrencyMode(value.AIConcurrencyMode), ProviderStepRetries: value.ProviderStepRetries, PriorityPolicy: contract.DocumentProcessingSchedulingPriorityPolicy(value.PriorityPolicy)}
}
