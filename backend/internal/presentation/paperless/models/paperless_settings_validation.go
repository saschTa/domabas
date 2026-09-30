package models

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"unicode/utf8"

	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

func ValidateSettings(body []byte) error {
	invalid := errors.New("invalid Paperless settings")
	if !utf8.Valid(body) {
		return invalid
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	if token, err := decoder.Token(); err != nil || token != json.Delim('{') {
		return invalid
	}
	seen := map[string]bool{}
	var update m.PaperlessSettingsUpdate
	for decoder.More() {
		token, err := decoder.Token()
		name, ok := token.(string)
		if err != nil || !ok || seen[name] {
			return invalid
		}
		seen[name] = true
		var raw json.RawMessage
		if decoder.Decode(&raw) != nil || bytes.Equal(raw, []byte("null")) {
			return invalid
		}
		switch name {
		case "retrievalConcurrency":
			if json.Unmarshal(raw, &update.RetrievalConcurrency) != nil {
				return invalid
			}
		case "expectedRevision":
			if json.Unmarshal(raw, &update.ExpectedRevision) != nil {
				return invalid
			}
		default:
			return invalid
		}
	}
	if token, err := decoder.Token(); err != nil || token != json.Delim('}') {
		return invalid
	}
	if decoder.Decode(new(any)) != io.EOF || !seen["retrievalConcurrency"] || !seen["expectedRevision"] {
		return invalid
	}
	return update.Validate()
}
