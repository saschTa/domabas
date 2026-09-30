package models

import (
	"strings"
	"testing"
)

func TestExtractionAcceptsExpandedPageAndTextBounds(t *testing.T) {
	configuration := DefaultConfiguration()
	for _, tc := range []struct {
		name         string
		pages, bytes int
		valid        bool
	}{
		{"maximum", 200, 2 << 20, true},
		{"too many pages", 201, 1, false},
		{"too much text", 1, (2 << 20) + 1, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			result := DocumentExtraction{
				Text: strings.Repeat("a", tc.bytes), Pages: tc.pages,
				ExtractionRevision: configuration.WithLegacyIdentity().ExtractionRevision,
				Engine:             configuration.Engine, EngineVersion: configuration.EngineVersion, Weights: configuration.Weights,
			}
			if err := configuration.ValidateExtraction("application/pdf", result); (err == nil) != tc.valid {
				t.Fatalf("valid=%v err=%v", tc.valid, err)
			}
		})
	}
}
