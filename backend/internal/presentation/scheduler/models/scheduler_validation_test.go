package models

import "testing"

func TestWorkloadSettingsRejectAmbiguousJSON(t *testing.T) {
	for _, body := range []string{
		`null`, `{}`, `{"expectedRevision":1,"resources":null}`,
		`{"expectedRevision":1,"resources":[]}`,
		`{"expectedRevision":1,"resources":[{"id":"worker","limit":1}],"unknown":true}`,
		`{"expectedRevision":1,"expectedRevision":2,"resources":[{"id":"worker","limit":1}]}`,
		`{"expectedRevision":1,"resources":[{"id":"worker","id":"ollama","limit":1}]}`,
		`{"expectedRevision":1,"resources":[{"id":"worker","limit":null}]}`,
		`{"expectedRevision":1,"resources":[{"id":"worker","limit":1.5}]}`,
		`{"expectedRevision":1,"resources":[{"id":"worker","limit":1},{"id":"worker","limit":2}]}`,
		`{"expectedRevision":1,"resources":[{"id":"worker","limit":257}]}`,
		`{"expectedRevision":1,"resources":[{"id":"worker","limit":1}]} {}`,
	} {
		if err := ValidateSettings([]byte(body)); err == nil {
			t.Errorf("accepted %s", body)
		}
	}
	for _, body := range []string{
		`{"expectedRevision":1,"resources":[{"id":"worker","limit":1}]}`,
		`{"resources":[{"limit":256,"id":"worker"},{"id":"ollama","limit":64}],"expectedRevision":42}`,
	} {
		if err := ValidateSettings([]byte(body)); err != nil {
			t.Errorf("rejected %s: %v", body, err)
		}
	}
}
