package services

import (
	"encoding/json"
	"fmt"
	"strings"
	"unicode/utf8"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
)

func chatInferenceMapper(work m.ChatWork) (m.ChatInferenceInput, error) {
	result := m.ChatInferenceInput{Configuration: work.Configuration, APIKey: work.APIKey, ToolsUsed: len(work.Tools), AnswerOnly: m.ChatToolsMustAnswer(work.Tools), Messages: []m.ChatProviderMessage{}}
	if len(work.Messages) == 0 || len(work.Tools) > m.ChatMaxToolCalls {
		return result, m.ChatProcessingError{Code: "resource_limit"}
	}
	var ledger strings.Builder
	for i, tool := range work.Tools {
		arguments, err := chatToolLedgerMapper(tool.Action)
		if err != nil {
			return result, err
		}
		fmt.Fprintf(&ledger, "%d: %s %s outcome=%s\n", i+1, tool.Action.Kind, arguments, tool.Outcome)
	}
	result.ToolLedger = ledger.String()
	latest := work.Messages[len(work.Messages)-1]
	budget := m.ChatMaxContextCharacters - 4000 - utf8.RuneCountInString(result.ToolLedger) - utf8.RuneCountInString(latest.Content)
	if budget < 0 {
		return result, m.ChatProcessingError{Code: "resource_limit"}
	}
	var evidence []m.ChatProviderMessage
	for i := len(work.Tools) - 1; i >= 0; i-- {
		tool := work.Tools[i]
		arguments, err := chatToolArgumentsMapper(tool.Action)
		if err != nil {
			return result, err
		}
		cost := utf8.RuneCountInString(tool.Content) + utf8.RuneCountInString(arguments) + 200
		if cost > budget || len(evidence)+3 > m.ChatMaxContextMessages {
			break
		}
		budget -= cost
		id := tool.Action.ToolCallID
		if id == "" {
			id = fmt.Sprintf("document-context-%d", i)
		}
		pair := []m.ChatProviderMessage{{Role: "assistant", ToolCall: &m.ChatToolCall{ID: id, Name: tool.Action.Kind, Arguments: arguments}}, {Role: "tool", Content: tool.Content, ToolCallID: id}}
		evidence = append(pair, evidence...)
	}
	history := []m.ChatProviderMessage{{Role: latest.Role, Content: latest.Content}}
	for i := len(work.Messages) - 2; i >= 0; i-- {
		v := work.Messages[i]
		cost := utf8.RuneCountInString(v.Content)
		if cost > budget || len(history)+len(evidence) >= m.ChatMaxContextMessages {
			break
		}
		budget -= cost
		history = append([]m.ChatProviderMessage{{Role: v.Role, Content: v.Content}}, history...)
	}
	result.Messages = append(history, evidence...)
	return result, nil
}

func chatToolLedgerMapper(action m.ChatAction) (string, error) {
	if utf8.RuneCountInString(action.Query) <= 120 {
		return chatToolArgumentsMapper(action)
	}
	body, err := json.Marshal(map[string]any{"queryPrefix": string([]rune(action.Query)[:120]), "offset": action.Offset})
	return string(body), err
}

func chatToolArgumentsMapper(action m.ChatAction) (string, error) {
	arguments := map[string]any{"offset": action.Offset}
	switch action.Kind {
	case "search_documents":
		arguments["query"] = action.Query
	case "read_document":
		arguments["documentId"] = action.DocumentID
	}
	body, err := json.Marshal(arguments)
	return string(body), err
}
