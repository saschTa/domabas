package models

import (
	"net/url"
	"strings"
	"unicode/utf8"
)

func ChatValidID(id string) bool {
	if len(id) != 36 || id == "00000000-0000-0000-0000-000000000000" {
		return false
	}
	for i, c := range id {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return false
			}
			continue
		}
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	return true
}
func ChatValidText(s string, limit int) bool {
	if !utf8.ValidString(s) || utf8.RuneCountInString(s) > limit || strings.ContainsRune(s, 0) {
		return false
	}
	for _, r := range s {
		if r < 32 && r != '\n' && r != '\r' && r != '\t' {
			return false
		}
	}
	return true
}
func (p ChatPageRequest) Normalize() (ChatPageRequest, error) {
	if p.Limit == 0 {
		p.Limit = 20
	}
	if p.Limit < 1 || p.Limit > 50 || len(p.Cursor) > 1024 {
		return p, ChatValidationError{"invalid chat page"}
	}
	return p, nil
}
func (u ChatConfigurationUpdate) Normalize() (ChatConfigurationUpdate, error) {
	u.Model = strings.TrimSpace(u.Model)
	u.BaseURL = strings.TrimRight(strings.TrimSpace(u.BaseURL), "/")
	if u.ExpectedRevision < 1 || !ChatValidModel(u.Model) {
		return u, ChatValidationError{"invalid chat model or revision"}
	}
	if u.ContextLength != nil && (*u.ContextLength < ChatMinimumContextLength || *u.ContextLength > ChatMaximumContextLength) {
		return u, ChatValidationError{"invalid chat context length"}
	}
	if u.Provider != "ollama" && u.Provider != "openai" {
		return u, ChatValidationError{"invalid chat provider"}
	}
	if u.Provider == "ollama" {
		if u.BaseURL != "" || u.APIKey != nil {
			return u, ChatValidationError{"internal Ollama uses no external endpoint or secret"}
		}
	} else {
		v, e := url.Parse(u.BaseURL)
		if e != nil || len(u.BaseURL) > 2048 || v.Hostname() == "" || (v.Scheme != "http" && v.Scheme != "https") || v.User != nil || v.RawQuery != "" || v.ForceQuery || v.Fragment != "" || strings.ContainsAny(u.BaseURL, "\\\r\n\t") {
			return u, ChatValidationError{"invalid provider base URL"}
		}
	}
	if u.APIKey != nil && (u.ClearAPIKey || *u.APIKey == "" || len(*u.APIKey) > 4096 || strings.TrimSpace(*u.APIKey) != *u.APIKey || strings.ContainsAny(*u.APIKey, "\r\n\x00")) {
		return u, ChatValidationError{"invalid provider secret"}
	}
	return u, nil
}
func ChatValidModel(model string) bool {
	return ChatValidText(model, 200) && model != "" && !strings.ContainsAny(model, "\r\n\t ")
}
func (v ChatSendInput) Validate() error {
	if !ChatValidID(v.RequestID) || strings.TrimSpace(v.Content) == "" || len(v.Content) > 32768 || !ChatValidText(v.Content, ChatMaxMessageCharacters) {
		return ChatValidationError{"invalid chat message"}
	}
	return nil
}
func (a ChatAction) Validate() error {
	switch a.Kind {
	case "answer":
		if strings.TrimSpace(a.Content) == "" || !ChatValidText(a.Content, 16000) {
			return ChatProcessingError{Code: "invalid_response"}
		}
	case "search_documents":
		if strings.TrimSpace(a.Query) == "" || !ChatValidText(a.Query, 500) || a.Offset < 0 || a.Offset > 10000 {
			return ChatProcessingError{Code: "invalid_response"}
		}
	case "read_document":
		if !ChatValidID(a.DocumentID) || a.Offset < 0 || a.Offset > 10000000 {
			return ChatProcessingError{Code: "invalid_response"}
		}
	case "list_tools":
		if a.Offset < 0 || a.Offset > 10000 || a.Content != "" || a.Query != "" || a.DocumentID != "" {
			return ChatProcessingError{Code: "invalid_response"}
		}
	default:
		return ChatProcessingError{Code: "invalid_response"}
	}
	return nil
}
