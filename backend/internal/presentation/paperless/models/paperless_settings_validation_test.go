package models

import "testing"

func TestPaperlessSettingsRequiresStrictBoundedRevisionAndConcurrency(t *testing.T) {
	for _, body := range []string{
		`{}`, `null`, `{"retrievalConcurrency":1}`, `{"retrievalConcurrency":1,"expectedRevision":null}`,
		`{"retrievalConcurrency":0,"expectedRevision":1}`, `{"retrievalConcurrency":11,"expectedRevision":1}`,
		`{"retrievalConcurrency":1.5,"expectedRevision":1}`, `{"retrievalConcurrency":1,"expectedRevision":0}`,
		`{"retrievalConcurrency":1,"expectedRevision":1,"extra":1}`, `{"retrievalConcurrency":1,"retrievalConcurrency":2,"expectedRevision":1}`,
		`{"retrievalConcurrency":1,"expectedRevision":1} {}`,
	} {
		if err := ValidateSettings([]byte(body)); err == nil {
			t.Errorf("accepted %s", body)
		}
	}
	for _, body := range []string{`{"retrievalConcurrency":1,"expectedRevision":1}`, `{"expectedRevision":2,"retrievalConcurrency":10}`} {
		if err := ValidateSettings([]byte(body)); err != nil {
			t.Errorf("rejected %s: %v", body, err)
		}
	}
}
