package models

import (
	"strings"
	"unicode/utf8"
)

func (input DocumentVocabularyInput) Normalize() (DocumentVocabularyInput, error) {
	if input.Field != "tag" && input.Field != "sender" && input.Field != "recipient" {
		return input, DocumentValidationError{Message: "invalid vocabulary field"}
	}
	if !utf8.ValidString(input.Query) {
		return input, DocumentValidationError{Message: "invalid vocabulary query"}
	}
	input.Query = strings.TrimSpace(input.Query)
	if !validText(input.Query, 320, 1280, false) {
		return input, DocumentValidationError{Message: "invalid vocabulary query"}
	}
	if input.Limit == 0 {
		input.Limit = 40
	}
	if input.Limit < 1 || input.Limit > 50 || !utf8.ValidString(input.Cursor) || len(input.Cursor) > 4096 {
		return input, DocumentValidationError{Message: "invalid vocabulary pagination"}
	}
	return input, nil
}

func ValidateVocabularyValue(field, value string) error {
	runes, bytes := 320, 1280
	if field == "tag" {
		runes, bytes = 64, 256
	}
	if value == "" || strings.TrimSpace(value) != value || !validText(value, runes, bytes, false) {
		return DocumentValidationError{Message: "invalid vocabulary value"}
	}
	if field == "tag" && strings.ToLower(value) != value {
		return DocumentValidationError{Message: "invalid vocabulary tag"}
	}
	return nil
}
