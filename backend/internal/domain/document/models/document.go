package models

import (
	"encoding/hex"
	"errors"
	"strings"
	"unicode/utf8"
)

var ErrNotFound = errors.New("document not found")

func (e DocumentValidationError) Error() string { return e.Message }

func (input DocumentCreateInput) Validate() error {
	if !utf8.ValidString(input.Title) || strings.TrimSpace(input.Title) == "" || utf8.RuneCountInString(input.Title) > 200 {
		return DocumentValidationError{"title must contain 1 to 200 characters and cannot be blank"}
	}
	if !utf8.ValidString(input.Description) || utf8.RuneCountInString(input.Description) > 4000 {
		return DocumentValidationError{"description must contain at most 4000 characters"}
	}
	return nil
}

func (page DocumentPageRequest) Validate() error {
	if page.Limit < 1 || page.Limit > 100 || page.Offset < 0 {
		return DocumentValidationError{"limit must be between 1 and 100 and offset must be nonnegative"}
	}
	if len(page.Cursor) > 4096 || (page.Cursor != "" && page.Offset != 0) {
		return DocumentValidationError{"invalid document cursor or pagination"}
	}
	return nil
}

func ValidateAccountID(id string) error {
	if len(id) != 36 || id[8] != '-' || id[13] != '-' || id[18] != '-' || id[23] != '-' {
		return DocumentValidationError{"account ID must be a UUID"}
	}
	raw, err := hex.DecodeString(strings.ReplaceAll(id, "-", ""))
	if err != nil || len(raw) != 16 || strings.Trim(id, "0-") == "" {
		return DocumentValidationError{"account ID must be a UUID"}
	}
	return nil
}
