package models

import (
	"strings"
	"testing"
)

func TestAuthenticationStrictBoundedWire(t *testing.T) {
	valid := `{"type":"authenticate","version":1,"token":"` + strings.Repeat("A", 43) + `"}`
	if _, err := Authentication([]byte(valid)); err != nil {
		t.Fatal(err)
	}
	for _, input := range []string{
		strings.Replace(valid, `"version":1`, `"version":1,"version":1`, 1),
		strings.Replace(valid, `"version":1`, `"version":1.0`, 1),
		strings.Replace(valid, `"version":1`, `"version":null`, 1),
		strings.Replace(valid, `"type":"authenticate"`, `"type":"authenticate","unknown":1`, 1),
		valid + `{}`, strings.Replace(valid, "authenticate", `\ud800`, 1), strings.Replace(valid, "authenticate", string([]byte{0xff}), 1), strings.Repeat(" ", 1025) + valid,
		strings.Replace(valid, strings.Repeat("A", 43), strings.Repeat("A", 42)+"B", 1),
	} {
		if _, err := Authentication([]byte(input)); err == nil {
			t.Fatalf("accepted invalid frame: %q", input)
		}
	}
}
