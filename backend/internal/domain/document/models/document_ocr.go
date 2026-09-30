package models

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

const MaxOCRBytes = 2 << 20
const MaxOCRChunks = 2048

func (input DocumentOCRCorrection) Validate() ([]DocumentChunk, error) {
	if input.Revision < 0 {
		return nil, DocumentValidationError{Message: "OCR revision must be nonnegative"}
	}
	return OCRChunks(input.Text)
}

func OCRChunks(text string) ([]DocumentChunk, error) {
	if !utf8.ValidString(text) || strings.ContainsRune(text, 0) {
		return nil, DocumentValidationError{Message: "OCR text must be valid UTF-8 without NUL"}
	}
	if len(text) > MaxOCRBytes {
		return nil, ErrTooLarge
	}
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) && r != '\n' && r != '\t' {
			return -1
		}
		return r
	}, text)
	text = strings.TrimSpace(text)
	runes := []rune(text)
	chunks := []DocumentChunk{}
	for start := 0; start < len(runes); {
		if len(chunks) >= MaxOCRChunks {
			return nil, ErrTooLarge
		}
		end := min(start+2048, len(runes))
		if end < len(runes) {
			for at := end; at > start+1536; at-- {
				if unicode.IsSpace(runes[at-1]) {
					end = at
					break
				}
			}
		}
		if value := strings.TrimSpace(string(runes[start:end])); value != "" {
			chunks = append(chunks, DocumentChunk{Position: len(chunks), Text: value})
		}
		if end == len(runes) {
			break
		}
		start = end - min(128, end-start-1)
	}
	return chunks, nil
}
