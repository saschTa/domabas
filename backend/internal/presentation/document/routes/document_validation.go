package routes

import (
	"bytes"
	"encoding/json"
	"errors"
	"unicode/utf8"

	"github.com/domabas/domabas/backend/internal/presentation/document/models"
)

func validateJSON(body []byte) error {
	var input models.DocumentCreateRequest
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil || input.Title == nil || !utf8.Valid(body) {
		return errors.New("body must be an object with a string title and optional string description")
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(body, &fields); err != nil || bytes.Equal(fields["description"], []byte("null")) {
		return errors.New("body must contain exactly one JSON object without null fields")
	}
	for key := range fields {
		if key != "title" && key != "description" {
			return errors.New("body contains an unknown field")
		}
	}
	return nil
}
