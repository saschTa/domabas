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
	document = slices.DeleteFunc(slices.Clone(document), func(id string) bool { return id == "worker" })
	return []SchedulerPipeline{
		{ID: "document_thumbnail", Label: "Document thumbnails", ResourceIDs: []string{"worker", "stage:thumbnail"}},
		{ID: "document_ingestion", Label: "Document ingestion", ResourceIDs: []string{"worker", "stage:thumbnail", "stage:ocr", "stage:embedding", "ollama"}},
		{ID: "document_ai", Label: "Document enrichment", ResourceIDs: []string{"worker", "pipeline:invoice", "pipeline:tags"}},
		{ID: "invoice", Label: "Invoice extraction", ResourceIDs: append([]string{"stage:llm"}, document...)},
		{ID: "tags", Label: "Tags and properties", ResourceIDs: append([]string{"stage:llm"}, document...)},
		{ID: "chat", Label: "AI chat", ResourceIDs: append([]string{"stage:llm"}, chat...)},
		{ID: "email", Label: "Email retrieval", ResourceIDs: []string{"worker"}},
		{ID: "paperless", Label: "Paperless imports", ResourceIDs: []string{"worker", "stage:paperless"}},
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
