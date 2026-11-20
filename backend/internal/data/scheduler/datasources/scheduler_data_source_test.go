package datasources

import (
	r "github.com/domabas/domabas/backend/internal/data/scheduler/models"
	"slices"
	"strings"
	"testing"
)

func TestSchedulerResourceOriginsShareCapacity(t *testing.T) {
	source := NewSchedulerDataSource(nil, 128)
	if source.ResourceID("embedding-runtime") != "embedding-runtime" {
		t.Fatal("missing embedding runtime")
	}
	first := source.ResourceID("HTTPS://Provider.Example.test:443/v1")
	if !strings.HasPrefix(first, "external:") || first != source.ResourceID("https://provider.example.test/another/path") {
		t.Fatalf("provider aliases differ: %q", first)
	}
	if first == source.ResourceID("http://provider.example.test") || first == source.ResourceID("https://provider.example.test:8443") {
		t.Fatal("distinct origins share resource")
	}
	if source.ResourceID("http://[::1]:80/v1") != source.ResourceID("http://[::1]/api") {
		t.Fatal("IPv6 default ports differ")
	}
	for _, invalid := range []string{"", "not a URL", "ftp://provider.test", "https://user:password@provider.test", "https://provider.test?key=private", "https://provider.test#secret", "https://provider.test:99999", "https://provider.test\\path"} {
		if got := source.ResourceID(invalid); got != "" {
			t.Fatalf("accepted invalid origin %q as %q", invalid, got)
		}
	}
}

func TestSchedulerRetainedRequirementsIncludeLegacyProviders(t *testing.T) {
	for _, scenario := range []struct {
		name, pipeline, snapshot string
		combined                 bool
		providers                []string
	}{
		{"split ingestion", "document_ingestion", "", false, []string{"embedding-runtime"}},
		{"legacy external", "document_ingestion", `{"LLM":{"Enabled":true,"Provider":"openai","BaseURL":"https://provider.test/v1"}}`, true, []string{"embedding-runtime", "https://provider.test/v1"}},
		{"invoice only", "document_ai", `{"LLM":{"Enabled":false,"InvoiceEnabled":true,"Provider":"openai","BaseURL":"https://provider.test/v1"}}`, false, []string{"https://provider.test/v1"}},
		{"xml only", "document_ai", `{"LLM":{"Enabled":false,"InvoiceEnabled":false,"Provider":"openai"}}`, false, []string{}},
		{"retrieval", "paperless", "", false, []string{}},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			got, err := retainedProviders(r.SchedulerRetainedExecution{Pipeline: scenario.pipeline, Configuration: []byte(scenario.snapshot), Combined: scenario.combined})
			if err != nil || !slices.Equal(got, scenario.providers) {
				t.Fatalf("providers=%v err=%v", got, err)
			}
		})
	}
	if _, err := retainedProviders(r.SchedulerRetainedExecution{Pipeline: "document_ingestion", Combined: true}); err == nil {
		t.Fatal("missing legacy snapshot must fail closed")
	}
}
