package models

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"unicode/utf8"
)

func Validate(body []byte) error {
	invalid := errors.New("provide a request ID, Paperless server URL and API token")
	if !utf8.Valid(body) {
		return invalid
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	if token, err := decoder.Token(); err != nil || token != json.Delim('{') {
		return invalid
	}
	seen := map[string]bool{}
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
		case "serverUrl", "token", "requestId":
			var value string
			if json.Unmarshal(raw, &value) != nil || value == "" || len(value) > 2048 {
				return invalid
			}
		default:
			return invalid
		}
	}
	if token, err := decoder.Token(); err != nil || token != json.Delim('}') {
		return invalid
	}
	if decoder.Decode(new(any)) != io.EOF || !seen["serverUrl"] || !seen["token"] || !seen["requestId"] {
		return invalid
	}
	return nil
}
