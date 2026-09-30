package models

import (
	"encoding/json"
	"errors"
	"strconv"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func DecodeOCR(body []byte) (domain.DocumentOCRCorrection, error) {
	var input domain.DocumentOCRCorrection
	if err := ValidateObject(body, "ocr"); err != nil {
		return input, err
	}
	if !validJSONUnicode(body) {
		return input, errors.New("body contains invalid Unicode escapes")
	}
	var request DocumentOCRRequest
	if err := json.Unmarshal(body, &request); err != nil {
		return input, errors.New("invalid OCR correction")
	}
	input = domain.DocumentOCRCorrection{Revision: request.Revision, Text: request.Text}
	_, err := input.Validate()
	return input, err
}

func validJSONUnicode(body []byte) bool {
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
