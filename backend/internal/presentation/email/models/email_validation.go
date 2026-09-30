package models

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"unicode/utf8"
)

func ValidateObject(body []byte, operation string) error {
	invalid := errors.New("email request must contain valid fields")
	if !utf8.Valid(body) {
		return invalid
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	token, err := decoder.Token()
	if err != nil || token != json.Delim('{') {
		return invalid
	}
	fields := map[string]json.RawMessage{}
	for decoder.More() {
		token, err := decoder.Token()
		name, ok := token.(string)
		if err != nil || !ok {
			return invalid
		}
		if _, exists := fields[name]; exists {
			return invalid
		}
		var raw json.RawMessage
		if decoder.Decode(&raw) != nil || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			return invalid
		}
		fields[name] = raw
	}
	if token, err = decoder.Token(); err != nil || token != json.Delim('}') || decoder.Decode(new(any)) != io.EOF {
		return invalid
	}
	required := []string{}
	optional := []string{}
	switch operation {
	case "create":
		required = []string{"id", "label", "endpoint", "port", "mailbox", "username", "password", "enabled", "intervalMinutes", "maxAgeDays", "pageSize"}
	case "update":
		required = []string{"expectedRevision", "label", "endpoint", "port", "mailbox", "enabled", "intervalMinutes", "maxAgeDays", "pageSize"}
		optional = []string{"username", "password", "renewConsent"}
	case "test":
		required = []string{"endpoint", "port", "mailbox"}
		optional = []string{"providerId", "expectedRevision", "username", "password"}
	case "run":
		required = []string{"requestId", "expectedRevision"}
	default:
		return invalid
	}
	allowed := map[string]bool{}
	for _, name := range required {
		allowed[name] = true
		if _, ok := fields[name]; !ok {
			return invalid
		}
	}
	for _, name := range optional {
		allowed[name] = true
	}
	for name, raw := range fields {
		if !allowed[name] {
			return invalid
		}
		switch name {
		case "port", "intervalMinutes", "maxAgeDays", "pageSize", "expectedRevision":
			var value int64
			if json.Unmarshal(raw, &value) != nil || value < 1 {
				return invalid
			}
			switch name {
			case "port":
				if value > 65535 {
					return invalid
				}
			case "intervalMinutes":
				if value < 5 || value > 1440 {
					return invalid
				}
			case "maxAgeDays":
				if value > 3650 {
					return invalid
				}
			case "pageSize":
				if value > 100 {
					return invalid
				}
			}
		case "enabled", "renewConsent":
			var value bool
			if json.Unmarshal(raw, &value) != nil {
				return invalid
			}
		default:
			var value string
			if json.Unmarshal(raw, &value) != nil || len(value) > 4096 || !utf8.ValidString(value) {
				return invalid
			}
			if name == "password" && value == "" {
				return invalid
			}
		}
	}
	return nil
}
