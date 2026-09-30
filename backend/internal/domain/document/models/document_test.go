package models_test

import (
	"strings"
	"testing"

	documentmodels "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestCreateValidationUsesUnicodeCharacters(t *testing.T) {
	for _, test := range []struct {
		name, title, description string
		valid                    bool
	}{
		{"normal", "Invoice", "September", true},
		{"unicode maximum", strings.Repeat("界", 200), strings.Repeat("🙂", 4000), true},
		{"unicode too long", strings.Repeat("界", 201), "", false},
		{"description too long", "Invoice", strings.Repeat("🙂", 4001), false},
		{"empty", "", "", false},
		{"unicode whitespace", " \t\u2003", "", false},
		{"invalid UTF8", "\xff", "", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			err := (documentmodels.DocumentCreateInput{Title: test.title, Description: test.description}).Validate()
			if (err == nil) != test.valid {
				t.Fatalf("valid=%v, error=%v", test.valid, err)
			}
		})
	}
}
