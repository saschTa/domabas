package models

import (
	"errors"
	"strings"
	"testing"
)

func TestOCRLimitsCountDecodedBytesAndDerivedChunksIndependently(t *testing.T) {
	for _, tc := range []struct {
		name  string
		text  string
		count int
		large bool
	}{
		{"empty", "", 0, false},
		{"control whitespace", " \r\n\t\x01\x7f ", 0, false},
		{"exact byte limit with no chunks", strings.Repeat("\t", MaxOCRBytes), 0, false},
		{"decoded byte overflow", strings.Repeat("\t", MaxOCRBytes+1), 0, true},
		{"256 overlapping chunks", strings.Repeat("x", 2048+255*1920), 256, false},
		{"past old chunk limit", strings.Repeat("x", 2049+255*1920), 257, false},
		{"2 MiB of searchable text", strings.Repeat("x", 2<<20), 1093, false},
		{"2 MiB with early word boundaries", strings.Repeat(strings.Repeat("a", 1536)+" ", (2<<20)/1537), 1364, false},
		{"multibyte byte overflow", strings.Repeat("世", MaxOCRBytes/3+1), 0, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			chunks, err := (DocumentOCRCorrection{Revision: 0, Text: tc.text}).Validate()
			if tc.large {
				if !errors.Is(err, ErrTooLarge) {
					t.Fatalf("expected size error, got %v", err)
				}
				return
			}
			if err != nil || len(chunks) != tc.count {
				t.Fatalf("chunks=%d want=%d err=%v", len(chunks), tc.count, err)
			}
		})
	}
	for _, text := range []string{"embedded\x00NUL", string([]byte{0xff}), "valid\xed\xa0\x80"} {
		if _, err := OCRChunks(text); err == nil {
			t.Fatal("invalid Unicode or NUL accepted")
		}
	}
}
