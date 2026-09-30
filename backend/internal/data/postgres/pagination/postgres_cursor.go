package pagination

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"strconv"
	"unicode/utf8"
)

const MaxEncodedBytes = 4096
const MaxDecodedBytes = 3072

var ErrInvalidCursor = errors.New("invalid pagination cursor")

type paginationCursorEnvelope struct {
	Version     int             `json:"v"`
	Operation   string          `json:"op"`
	Fingerprint string          `json:"fp"`
	Sort        string          `json:"sort"`
	Key         json.RawMessage `json:"key"`
}

func Fingerprint(value any) (string, error) {
	body, err := json.Marshal(value)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(body)
	return hex.EncodeToString(digest[:]), nil
}

func Encode(operation, fingerprint, sort string, key any) (string, error) {
	return EncodeBounded(operation, fingerprint, sort, key, MaxEncodedBytes)
}

func EncodeBounded(operation, fingerprint, sort string, key any, maxBytes int) (string, error) {
	body, err := json.Marshal(key)
	if err != nil {
		return "", ErrInvalidCursor
	}
	body, err = json.Marshal(paginationCursorEnvelope{1, operation, fingerprint, sort, body})
	if err != nil || len(body) > maxBytes*3/4 {
		return "", ErrInvalidCursor
	}
	token := base64.RawURLEncoding.EncodeToString(body)
	if _, err = DecodeBounded(token, operation, fingerprint, sort, maxBytes); err != nil {
		return "", err
	}
	return token, nil
}

func Decode(token, operation, fingerprint, sort string) (map[string]json.RawMessage, error) {
	return DecodeBounded(token, operation, fingerprint, sort, MaxEncodedBytes)
}

func DecodeBounded(token, operation, fingerprint, sort string, maxBytes int) (map[string]json.RawMessage, error) {
	if len(token) == 0 || len(token) > maxBytes {
		return nil, ErrInvalidCursor
	}
	body, err := base64.RawURLEncoding.Strict().DecodeString(token)
	if err != nil || len(body) > maxBytes*3/4 || base64.RawURLEncoding.EncodeToString(body) != token {
		return nil, ErrInvalidCursor
	}
	fields, err := boundedObject(body, maxBytes*3/4)
	if err != nil || len(fields) != 5 {
		return nil, ErrInvalidCursor
	}
	for _, name := range []string{"v", "op", "fp", "sort", "key"} {
		if _, ok := fields[name]; !ok {
			return nil, ErrInvalidCursor
		}
	}
	var value paginationCursorEnvelope
	if json.Unmarshal(body, &value) != nil || value.Version != 1 || value.Operation != operation || value.Sort != sort || value.Fingerprint != fingerprint || len(value.Fingerprint) != 64 {
		return nil, ErrInvalidCursor
	}
	for _, c := range value.Fingerprint {
		if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') {
			return nil, ErrInvalidCursor
		}
	}
	return boundedObject(value.Key, maxBytes*3/4)
}

func Object(body []byte) (map[string]json.RawMessage, error) {
	return boundedObject(body, MaxDecodedBytes)
}

func boundedObject(body []byte, maxBytes int) (map[string]json.RawMessage, error) {
	if len(body) > maxBytes || !utf8.Valid(body) || !validUnicode(body) {
		return nil, ErrInvalidCursor
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	start, err := decoder.Token()
	if err != nil || start != json.Delim('{') {
		return nil, ErrInvalidCursor
	}
	fields := map[string]json.RawMessage{}
	for decoder.More() {
		token, err := decoder.Token()
		name, ok := token.(string)
		if err != nil || !ok {
			return nil, ErrInvalidCursor
		}
		if _, duplicate := fields[name]; duplicate {
			return nil, ErrInvalidCursor
		}
		var raw json.RawMessage
		if decoder.Decode(&raw) != nil || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			return nil, ErrInvalidCursor
		}
		fields[name] = raw
	}
	if end, err := decoder.Token(); err != nil || end != json.Delim('}') {
		return nil, ErrInvalidCursor
	}
	var trailing any
	if decoder.Decode(&trailing) != io.EOF {
		return nil, ErrInvalidCursor
	}
	return fields, nil
}

func validUnicode(body []byte) bool {
	inString := false
	for i := 0; i < len(body); i++ {
		if body[i] == '"' {
			inString = !inString
			continue
		}
		if !inString || body[i] != '\\' {
			continue
		}
		i++
		if i >= len(body) {
			return false
		}
		if body[i] != 'u' {
			continue
		}
		if i+4 >= len(body) {
			return false
		}
		value, err := strconv.ParseUint(string(body[i+1:i+5]), 16, 16)
		if err != nil {
			return false
		}
		i += 4
		if value >= 0xDC00 && value <= 0xDFFF {
			return false
		}
		if value < 0xD800 || value > 0xDBFF {
			continue
		}
		if i+6 >= len(body) || body[i+1] != '\\' || body[i+2] != 'u' {
			return false
		}
		low, err := strconv.ParseUint(string(body[i+3:i+7]), 16, 16)
		if err != nil || low < 0xDC00 || low > 0xDFFF {
			return false
		}
		i += 6
	}
	return !inString
}
