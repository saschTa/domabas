package models

import (
	"slices"
	"testing"
)

func TestDocumentSearchKindsNormalizeAndRejectUnknownValues(t *testing.T) {
	for _, test := range []struct {
		input, want []string
	}{
		{nil, []string{}},
		{[]string{}, []string{}},
		{[]string{"email"}, []string{"email"}},
		{[]string{"letter", "document", "letter"}, []string{"document", "letter"}},
		{[]string{"letter", "email", "document"}, []string{}},
	} {
		original := slices.Clone(test.input)
		got, err := (DocumentSearchInput{Mode: "hybrid", Kinds: test.input}).Normalize()
		if err != nil || !slices.Equal(got.Kinds, test.want) || !slices.Equal(original, test.input) {
			t.Fatalf("kinds %v: got %v, want %v, err %v", test.input, got.Kinds, test.want, err)
		}
	}
	for _, invalid := range [][]string{{""}, {"EMAIL"}, {" email "}, {"pdf"}, {"document", "letter", "email", "email"}} {
		if _, err := (DocumentSearchInput{Mode: "fulltext", Kinds: invalid}).Normalize(); err == nil {
			t.Fatalf("accepted invalid kinds %v", invalid)
		}
	}
}
