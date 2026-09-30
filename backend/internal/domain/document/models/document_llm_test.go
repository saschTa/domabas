package models

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestLMStudioCompatibilityKeepsOldSnapshotsAndManifestIdentity(t *testing.T) {
	c := DefaultConfiguration()
	c.LLM.Provider, c.LLM.BaseURL = "openai", "http://model.test/v1"
	before, err := c.CanonicalFingerprint()
	if err != nil {
		t.Fatal(err)
	}
	manifest, _ := c.ManifestFingerprint()
	encoded, _ := json.Marshal(c)
	if strings.Contains(string(encoded), "LMStudioCompatibility") {
		t.Fatal("false added a field to legacy protocol snapshots")
	}
	var retained DocumentProcessingConfiguration
	if err := json.Unmarshal(encoded, &retained); err != nil || retained.LLM.LMStudioCompatibility {
		t.Fatal("legacy snapshot did not default to standard output", err)
	}
	c.LLM.LMStudioCompatibility = true
	after, err := c.CanonicalFingerprint()
	if err != nil || before == after || c.LLM.Equal(retained.LLM) {
		t.Fatal("compatibility missing from settings identity", err)
	}
	if got, _ := c.ManifestFingerprint(); got != manifest {
		t.Fatal("compatibility changed OCR or embedding identity")
	}
	encoded, _ = json.Marshal(c)
	if err := json.Unmarshal(encoded, &retained); err != nil || !retained.LLM.LMStudioCompatibility {
		t.Fatal("accepted compatibility setting lost", err)
	}
	if got, _ := retained.CanonicalFingerprint(); got != after {
		t.Fatal("snapshot round trip changed compatibility fingerprint")
	}
}

func TestLLMDefaultsValidationAndFingerprintCompatibility(t *testing.T) {
	base := DefaultConfiguration()
	if base.LLM.Enabled || base.LLM.InvoiceExtractionEnabled() || base.LLM.Defaults().Model != "qwen3.5:4b" {
		t.Fatal("optional extraction must default off")
	}
	base.LLM = DocumentLLMConfiguration{}
	if base.LLM.Defaults().Model != "gemma3:4b" {
		t.Fatal("historical snapshots must retain their model")
	}
	initial, _ := base.CanonicalFingerprint()
	base.LLM = base.LLM.Defaults()
	if got, _ := base.CanonicalFingerprint(); got != initial {
		t.Fatal("explicit defaults changed legacy fingerprints")
	}
	manifest, _ := base.ManifestFingerprint()
	base.LLM.Enabled = true
	if got, _ := base.CanonicalFingerprint(); got == initial {
		t.Fatal("enabled extraction omitted from identity")
	}
	if got, _ := base.ManifestFingerprint(); got != manifest {
		t.Fatal("LLM changed installed OCR manifest")
	}
	if _, err := base.ExtractionIdentity("application/pdf"); err != nil {
		t.Fatal(err)
	}
	for _, uri := range []string{"https://example.test/v1", "http://127.0.0.1:1234/v1", "http://model.internal/v1"} {
		if err := (DocumentLLMConfiguration{Provider: "openai", Model: "test", BaseURL: uri}).Validate(); err != nil {
			t.Fatal(uri, err)
		}
	}
	for _, uri := range []string{"", "file:///tmp/token", "https://user:secret@example.test/v1", "https://example.test/v1?key=x", "https://example.test/#fragment", "http://example.test:0/v1", "https://example.test:99999/v1", "http://example.test/v1\n"} {
		if err := (DocumentLLMConfiguration{Provider: "openai", Model: "test", BaseURL: uri}).Validate(); err == nil {
			t.Fatalf("accepted invalid URL %q", uri)
		}
	}
	for _, model := range []string{"bad model", strings.Repeat("x", 129), "bad\nmodel"} {
		if err := (DocumentLLMConfiguration{Model: model}).Validate(); err == nil {
			t.Fatal("accepted invalid model")
		}
	}
}

func TestLLMCredentialUpdateValidation(t *testing.T) {
	key := "secret"
	valid := DocumentLLMConfigurationUpdate{Provider: "openai", Model: "fixture", BaseURL: "https://example.test/v1/", APIKey: &key}
	normalized, err := valid.Normalize()
	if err != nil || normalized.BaseURL != "https://example.test/v1" {
		t.Fatal(normalized, err)
	}
	valid.ClearAPIKey = true
	if _, err := valid.Normalize(); err == nil {
		t.Fatal("accepted conflicting key operations")
	}
	valid.ClearAPIKey = false
	for _, bad := range []string{"", " secret", "secret\r\nInjected: true", strings.Repeat("k", 4097)} {
		valid.APIKey = &bad
		if _, err := valid.Normalize(); err == nil {
			t.Fatal("accepted invalid credential")
		}
	}
}

func TestLLMContextValidationAndSnapshotDefaults(t *testing.T) {
	if DefaultConfiguration().LLM.RequestedContextLength() != 32768 || (DocumentLLMConfiguration{}).RequestedContextLength() != 16384 {
		t.Fatal("new and historical context defaults lost their distinct meaning")
	}
	for _, tokens := range []int{-1, 0, 1023, 1048577} {
		if _, err := (DocumentLLMConfigurationUpdate{Provider: "ollama", Model: "qwen3.5:4b", ContextLength: &tokens}).Normalize(); err == nil {
			t.Fatalf("invalid context update accepted: %d", tokens)
		}
	}
	for _, tokens := range []int{1024, 32768, 1048576} {
		if _, err := (DocumentLLMConfigurationUpdate{Provider: "ollama", Model: "qwen3.5:4b", ContextLength: &tokens}).Normalize(); err != nil {
			t.Fatalf("valid context update rejected: %d %v", tokens, err)
		}
	}
	if _, err := (DocumentLLMConfigurationUpdate{Provider: "ollama", Model: "qwen3.5:4b"}).Normalize(); err != nil {
		t.Fatal("old client omission rejected", err)
	}
}

func TestIndependentInvoiceSettingsPreserveLegacyIdentity(t *testing.T) {
	fingerprints := map[string]bool{}
	for _, properties := range []bool{false, true} {
		legacy := DefaultConfiguration()
		legacy.LLM.Enabled = properties
		legacyFingerprint, err := legacy.CanonicalFingerprint()
		if err != nil {
			t.Fatal(err)
		}
		for _, invoices := range []bool{false, true} {
			current := legacy
			current.LLM.InvoiceEnabled = new(invoices)
			fingerprint, err := current.CanonicalFingerprint()
			if err != nil || fingerprints[fingerprint] {
				t.Fatalf("independent settings lost identity: %v", err)
			}
			fingerprints[fingerprint] = true
			if (fingerprint == legacyFingerprint) != (properties == invoices) || current.LLM.InvoiceExtractionEnabled() != invoices {
				t.Fatal("retained settings changed meaning")
			}
			copy := current.LLM
			copy.InvoiceEnabled = new(invoices)
			if !current.LLM.Equal(copy) || current.LLM.Equal(legacy.LLM) != (properties == invoices) {
				t.Fatal("configuration equality depends on pointer identity")
			}
		}
	}
}

func TestThinkingKeepsHistoricalFingerprintsAndIndependentSnapshots(t *testing.T) {
	c := DefaultConfiguration()
	legacy, _ := c.CanonicalFingerprint()
	manifest, _ := c.ManifestFingerprint()
	encoded, _ := json.Marshal(c)
	if strings.Contains(string(encoded), "ThinkingEnabled") {
		t.Fatal("false added a field to legacy snapshots")
	}
	fingerprints := map[string]bool{}
	for _, properties := range []bool{false, true} {
		for _, invoices := range []bool{false, true} {
			c.LLM.PropertyThinkingEnabled, c.LLM.InvoiceThinkingEnabled = properties, invoices
			fingerprint, err := c.CanonicalFingerprint()
			if err != nil || fingerprints[fingerprint] || (fingerprint == legacy) != (!properties && !invoices) {
				t.Fatal("thinking preferences lost independent identity", err)
			}
			fingerprints[fingerprint] = true
			if got, _ := c.ManifestFingerprint(); got != manifest {
				t.Fatal("thinking changed OCR identity")
			}
			encoded, _ := json.Marshal(c)
			var retained DocumentProcessingConfiguration
			if err := json.Unmarshal(encoded, &retained); err != nil || !retained.LLM.Equal(c.LLM) {
				t.Fatal("thinking snapshot lost", err)
			}
		}
	}
}
