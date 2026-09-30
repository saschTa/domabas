package models

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"unicode/utf8"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func WithUploadBody(ctx context.Context, reader io.Reader) context.Context {
	return context.WithValue(ctx, documentUploadBodyKey{}, DocumentUploadBody{Reader: reader})
}
func RemainingUploadBody(ctx context.Context) io.Reader {
	value, _ := ctx.Value(documentUploadBodyKey{}).(DocumentUploadBody)
	return value.Reader
}

func ValidateObject(body []byte, operation string) error {
	if !utf8.Valid(body) {
		return errors.New("body must contain valid UTF-8 JSON")
	}
	if (operation == "search" || operation == "configuration" || operation == "llm" || operation == "unlock") && !validJSONUnicode(body) {
		return errors.New("body contains invalid Unicode escapes")
	}
	fields := map[string]string{}
	required := []string{}
	switch operation {
	case "upload", "update":
		for _, key := range []string{"title", "description", "kind", "sender", "documentDate", "subject", "messageId"} {
			fields[key] = "string"
		}
		for _, key := range []string{"tags", "recipients", "cc", "bcc"} {
			fields[key] = "array"
		}
		if operation == "upload" {
			required = []string{"title"}
		}
	case "search":
		fields = map[string]string{"query": "string", "mode": "string", "tags": "array", "kinds": "array", "limit": "integer", "offset": "integer", "sender": "string", "recipient": "string", "senderMatch": "string", "recipientMatch": "string", "sort": "string", "cursor": "string"}
		required = []string{"query", "mode"}
	case "ocr":
		fields = map[string]string{"revision": "integer", "text": "string"}
		required = []string{"revision", "text"}
	case "configuration":
		fields = map[string]string{"language": "string", "segmentation": "string", "expectedRevision": "integer", "llm": "llm"}
		required = []string{"language", "segmentation"}
	case "llm":
		fields = map[string]string{"enabled": "boolean", "invoiceEnabled": "boolean", "lmStudioCompatibility": "boolean", "propertyThinkingEnabled": "boolean", "invoiceThinkingEnabled": "boolean", "contextLength": "integer", "provider": "string", "model": "string", "baseUrl": "string", "apiKey": "string", "clearApiKey": "boolean"}
		required = []string{"enabled", "provider", "model", "baseUrl"}
	case "unlock":
		fields = map[string]string{"password": "string", "generation": "integer"}
		required = []string{"password", "generation"}
	case "reindex":
		fields = map[string]string{"requestId": "string", "configurationRevision": "integer"}
		required = []string{"requestId", "configurationRevision"}
	default:
		return errors.New("unknown document operation")
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	first, err := decoder.Token()
	if err != nil || first != json.Delim('{') {
		return errors.New("body must contain one JSON object")
	}
	seen := map[string]bool{}
	for decoder.More() {
		keyToken, err := decoder.Token()
		key, ok := keyToken.(string)
		kind, known := fields[key]
		if err != nil || !ok || !known || seen[key] {
			return errors.New("body contains an unknown or duplicate field")
		}
		seen[key] = true
		var raw json.RawMessage
		if decoder.Decode(&raw) != nil || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			return errors.New("fields cannot be null")
		}
		switch kind {
		case "llm":
			if err := ValidateObject(raw, "llm"); err != nil {
				return err
			}
		case "boolean":
			var value bool
			if json.Unmarshal(raw, &value) != nil {
				return errors.New("field must be a boolean")
			}
		case "string":
			var value string
			if json.Unmarshal(raw, &value) != nil {
				return errors.New("field must be a string")
			}
		case "integer":
			var value int64
			if json.Unmarshal(raw, &value) != nil {
				return errors.New("field must be an integer")
			}
		case "array":
			var values []json.RawMessage
			if json.Unmarshal(raw, &values) != nil {
				return errors.New("field must be an array of strings")
			}
			for _, item := range values {
				var value string
				if bytes.Equal(bytes.TrimSpace(item), []byte("null")) || json.Unmarshal(item, &value) != nil {
					return errors.New("field must be an array of strings")
				}
			}
		}
	}
	if end, err := decoder.Token(); err != nil || end != json.Delim('}') {
		return errors.New("body must contain one JSON object")
	}
	var trailing any
	if decoder.Decode(&trailing) != io.EOF {
		return errors.New("body must contain one JSON object")
	}
	for _, key := range required {
		if !seen[key] {
			return errors.New("body is missing a required field")
		}
	}
	if operation == "update" && len(seen) == 0 {
		return errors.New("metadata patch must contain a field")
	}
	return nil
}

func DecodeMetadata(body []byte) (domain.DocumentMetadata, error) {
	if err := ValidateObject(body, "upload"); err != nil {
		return domain.DocumentMetadata{}, err
	}
	var request DocumentMetadataRequest
	if err := json.Unmarshal(body, &request); err != nil {
		return domain.DocumentMetadata{}, err
	}
	metadata := domain.DocumentMetadata{Title: *request.Title, Kind: "document"}
	patch := domain.DocumentMetadataPatch{Title: request.Title, Description: request.Description, Kind: request.Kind, Sender: request.Sender, DocumentDate: request.DocumentDate, Subject: request.Subject, MessageID: request.MessageID, Tags: request.Tags, Recipients: request.Recipients, CC: request.CC, BCC: request.BCC}
	return patch.Apply(metadata)
}
