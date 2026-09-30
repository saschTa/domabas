package models

import "strings"

func ChatSearchQueryKey(query string) string {
	return strings.ToLower(strings.Join(strings.Fields(query), " "))
}

func (result ChatToolResult) Executed() bool {
	switch result.Outcome {
	case "progress", "empty_result", "no_new_evidence", "document_unavailable":
		return true
	default:
		return false
	}
}

func ChatToolsMustAnswer(tools []ChatToolResult) bool {
	if len(tools) >= ChatMaxToolCalls {
		return true
	}
	stalled := 0
	for i := len(tools) - 1; i >= 0; i-- {
		if tools[i].Outcome == "progress" {
			break
		}
		stalled++
	}
	return stalled >= ChatMaxNoProgressCalls
}

func ChatToolRejection(action ChatAction, tools []ChatToolResult) string {
	knownDocument, continuation := false, action.Offset == 0
	for _, tool := range tools {
		prior := tool.Action
		same := action.Kind == prior.Kind
		switch action.Kind {
		case "search_documents":
			same = same && ChatSearchQueryKey(action.Query) == ChatSearchQueryKey(prior.Query)
		case "read_document":
			same = same && action.DocumentID == prior.DocumentID
		}
		if same && action.Offset == prior.Offset && tool.Executed() {
			return "repeated_call"
		}
		if same && tool.NextOffset != nil && action.Offset == *tool.NextOffset {
			continuation = true
		}
		if prior.Kind == "search_documents" {
			for _, source := range tool.Sources {
				knownDocument = knownDocument || source.DocumentID == action.DocumentID
			}
		}
	}
	if action.Kind == "search_documents" {
		switch ChatSearchQueryKey(action.Query) {
		case "document_unavailable", "unknown_document", "invalid_offset", "repeated_call", "error_query", "empty_result", "no_new_evidence":
			return "error_query"
		}
	}
	if action.Kind == "read_document" && !knownDocument {
		return "unknown_document"
	}
	if !continuation {
		return "invalid_offset"
	}
	return ""
}
