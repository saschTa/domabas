package models

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"strconv"
	"unicode/utf8"
)

func Authentication(body []byte) (string, error) {
	invalid := errors.New("invalid authentication frame")
	if len(body) > 1024 || !utf8.Valid(body) || !validSurrogates(body) {
		return "", invalid
	}
	d := json.NewDecoder(bytes.NewReader(body))
	first, err := d.Token()
	if err != nil || first != json.Delim('{') {
		return "", invalid
	}
	fields := map[string]json.RawMessage{}
	for d.More() {
		key, err := d.Token()
		if err != nil {
			return "", invalid
		}
		name, ok := key.(string)
		if !ok || (name != "type" && name != "version" && name != "token") || fields[name] != nil {
			return "", invalid
		}
		var raw json.RawMessage
		if d.Decode(&raw) != nil || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			return "", invalid
		}
		fields[name] = raw
	}
	if _, err = d.Token(); err != nil || d.Decode(new(any)) != io.EOF || len(fields) != 3 || string(fields["version"]) != "1" {
		return "", invalid
	}
	var kind, token string
	if json.Unmarshal(fields["type"], &kind) != nil || kind != "authenticate" || json.Unmarshal(fields["token"], &token) != nil || len(token) != 43 {
		return "", invalid
	}
	decoded, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(decoded) != 32 || base64.RawURLEncoding.EncodeToString(decoded) != token {
		return "", invalid
	}
	return token, nil
}
func validSurrogates(body []byte) bool {
	for i := 0; i < len(body); i++ {
		if body[i] != '\\' {
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
		n, err := strconv.ParseUint(string(body[i+1:i+5]), 16, 16)
		if err != nil {
			return false
		}
		i += 4
		if n >= 0xdc00 && n <= 0xdfff {
			return false
		}
		if n >= 0xd800 && n <= 0xdbff {
			if i+6 >= len(body) || body[i+1] != '\\' || body[i+2] != 'u' {
				return false
			}
			low, err := strconv.ParseUint(string(body[i+3:i+7]), 16, 16)
			if err != nil || low < 0xdc00 || low > 0xdfff {
				return false
			}
			i += 6
		}
	}
	return true
}
