package services

import (
	"encoding/json"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
)

func chatToolEvidenceMapper(action m.ChatAction, prior []m.ChatToolResult, evidence m.ChatToolEvidence) (m.ChatToolResult, error) {
	result := m.ChatToolResult{Action: action, Content: evidence.Content, Sources: evidence.Sources, NextOffset: evidence.NextOffset, Outcome: "progress"}
	if !evidence.Available {
		result.Outcome = "document_unavailable"
		result.Content = chatToolFeedbackMapper(result.Outcome)
		return result, nil
	}
	if evidence.Empty {
		result.Outcome = "empty_result"
	}
	if action.Kind == "search_documents" && !evidence.Empty {
		known := map[string]bool{}
		for _, tool := range prior {
			for _, source := range tool.Sources {
				known[source.DocumentID] = true
			}
		}
		result.Outcome = "no_new_evidence"
		for _, source := range evidence.Sources {
			if !known[source.DocumentID] {
				result.Outcome = "progress"
			}
		}
	}
	guidance := ""
	if action.Kind == "search_documents" {
		switch result.Outcome {
		case "empty_result":
			guidance = "No documents matched. Do not repeat this query or advance its offset. Try one distinctive word from the user's question, or answer that the requested evidence could not be found."
		case "no_new_evidence":
			guidance = "These documents were already found. Read a returned document that you have not read, use a returned continuation, or answer from the available evidence."
		}
	}
	if guidance != "" {
		var payload map[string]any
		if err := json.Unmarshal([]byte(result.Content), &payload); err != nil {
			return m.ChatToolResult{}, err
		}
		payload["guidance"] = guidance
		body, err := json.Marshal(payload)
		if err != nil {
			return m.ChatToolResult{}, err
		}
		result.Content = string(body)
	}
	return result, nil
}
