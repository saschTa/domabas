package models

import (
	"fmt"
	"slices"
)

func SchedulerResourceRequirements(providers []SchedulerProviderResource) ([]string, []SchedulerResource, error) {
	resources := []string{"worker"}
	defaults := []SchedulerResource{}
	for _, provider := range providers {
		if provider.ID == "" {
			return nil, nil, SchedulerValidationError{Message: "invalid workload provider origin"}
		}
		if slices.Contains(resources, provider.ID) {
			continue
		}
		resources = append(resources, provider.ID)
		if provider.ID != "ollama" {
			defaults = append(defaults, SchedulerResource{ID: provider.ID, Label: provider.Origin, Limit: SchedulerExternalDefaultLimit, MaximumLimit: SchedulerMaximumLimit})
		}
	}
	slices.Sort(resources)
	return resources, defaults, nil
}

func SchedulerConfiguredProviders(provider, baseURL string) []string {
	if provider == "" {
		return nil
	}
	if provider == "ollama" {
		return []string{"ollama"}
	}
	return []string{baseURL}
}

func SchedulerPipelineRequirements(document, chat []string) []SchedulerPipeline {
	return []SchedulerPipeline{
		{ID: "document_thumbnail", Label: "Document thumbnails", ResourceIDs: []string{"worker"}},
		{ID: "document_ingestion", Label: "Document ingestion", ResourceIDs: []string{"worker", "ollama"}},
		{ID: "document_ai", Label: "Document AI", ResourceIDs: document},
		{ID: "chat", Label: "AI chat", ResourceIDs: chat},
		{ID: "email", Label: "Email retrieval", ResourceIDs: []string{"worker"}},
		{ID: "paperless", Label: "Paperless imports", ResourceIDs: []string{"worker"}},
	}
}

func SchedulerRetainedProviders(configuration SchedulerRetainedConfiguration) ([]string, error) {
	providers := []string{}
	if configuration.Pipeline == "document_ingestion" {
		providers = append(providers, "ollama")
	}
	if configuration.Pipeline == "chat" {
		return SchedulerConfiguredProviders(configuration.Provider, configuration.BaseURL), nil
	}
	if configuration.Pipeline != "document_ai" && !configuration.Combined {
		return providers, nil
	}
	if !configuration.SnapshotPresent {
		return nil, fmt.Errorf("retained %s workload has no provider snapshot", configuration.Pipeline)
	}
	if configuration.PropertiesEnabled || configuration.InvoicesEnabled {
		provider := "ollama"
		if configuration.LLMProvider == "openai" {
			provider = configuration.LLMBaseURL
		}
		providers = append(providers, provider)
	}
	return providers, nil
}
