package models

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"unicode/utf8"
)

func ValidateChatObject(body []byte, operation string) error {
	invalid := errors.New("provide the required chat fields without duplicates or unknown properties")
	if !utf8.Valid(body) {
		return invalid
	}
	fields := map[string]string{}
	required := []string{}
	switch operation {
	case "create":
		fields["requestId"] = "string"
		required = []string{"requestId"}
	case "send":
		fields["requestId"] = "string"
		fields["content"] = "string"
		required = []string{"requestId", "content"}
	case "settings":
		fields = map[string]string{"expectedRevision": "number", "contextLength": "number", "enabled": "bool", "thinkingEnabled": "bool", "provider": "string", "model": "string", "baseUrl": "string", "apiKey": "string", "clearApiKey": "bool"}
		required = []string{"expectedRevision", "enabled", "provider", "model", "baseUrl"}
	default:
		return invalid
	}
	d := json.NewDecoder(bytes.NewReader(body))
	if token, err := d.Token(); err != nil || token != json.Delim('{') {
		return invalid
	}
	seen := map[string]bool{}
	for d.More() {
		token, err := d.Token()
		name, ok := token.(string)
		if err != nil || !ok || seen[name] {
			return invalid
		}
		seen[name] = true
		var raw json.RawMessage
		if d.Decode(&raw) != nil {
			return invalid
		}
		if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			if operation == "settings" && (name == "apiKey" || name == "clearApiKey") {
				continue
			}
			return invalid
		}
		switch fields[name] {
		case "string":
			var value string
			if json.Unmarshal(raw, &value) != nil {
				return invalid
			}
		case "bool":
			var value bool
			if json.Unmarshal(raw, &value) != nil {
				return invalid
			}
		case "number":
			var value int64
			if json.Unmarshal(raw, &value) != nil || value < 1 {
				return invalid
			}
		default:
			return invalid
		}
	}
	if token, err := d.Token(); err != nil || token != json.Delim('}') {
		return invalid
	}
	if d.Decode(new(any)) != io.EOF {
		return invalid
	}
	for _, name := range required {
		if !seen[name] {
			return invalid
		}
	}
	return nil
}
