//go:build integration

package repos_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestEmbeddingUpgradePreservesExternalConsentAndSchedulesOneReindex(t *testing.T) {
	for _, provider := range []string{"ollama", "openai"} {
		t.Run(provider, func(t *testing.T) {
			f := newIngestionFixture(t)
			source := llmSource(t, f)
			ctx := t.Context()
			legacy, err := f.service.GetProcessingConfiguration(ctx, f.actor)
			if err != nil {
				t.Fatal(err)
			}
			legacy.ManifestRevision = 2
			legacy.EmbeddingDigest = "0a109f422b47e3a30ba2b10eca18548e944e8a23073ee3f3e947efcf3c45e59f"
			legacy.LLM = m.DocumentLLMConfiguration{Provider: provider, Enabled: true, Model: "retained-model", ContextLength: 32768}
			if provider == "openai" {
				legacy.LLM.BaseURL = "https://saved.test/v1"
			}
			legacy.Fingerprint, err = legacy.CanonicalFingerprint()
			if err != nil {
				t.Fatal(err)
			}
			manifest, err := legacy.ManifestFingerprint()
			if err != nil {
				t.Fatal(err)
			}
			encoded, err := json.Marshal(legacy)
			if err != nil {
				t.Fatal(err)
			}
			f.exec(t, `UPDATE document_processing_configuration SET configuration=$1,fingerprint=$2,manifest_revision=2,manifest_fingerprint=$3,automatic_batch_id=NULL WHERE id`, encoded, legacy.Fingerprint, manifest)
			f.exec(t, `UPDATE document_processing_configurations SET configuration=$1,fingerprint=$2 WHERE revision=$3`, encoded, legacy.Fingerprint, legacy.Revision)
			for range 2 {
				if err := initializeDocumentSource(ctx, source); err != nil {
					t.Fatal(err)
				}
			}
			current, err := f.service.GetProcessingConfiguration(ctx, f.actor)
			if err != nil {
				t.Fatal(err)
			}
			if current.Revision != legacy.Revision+1 || current.ManifestRevision != 3 || current.EmbeddingDigest == legacy.EmbeddingDigest || current.AutomaticBatchID == "" {
				t.Fatal("incompatible embedding upgrade was not enrolled", current)
			}
			if provider == "openai" {
				if !current.LLM.Equal(legacy.LLM) {
					t.Fatal("saved external connection changed", current.LLM)
				}
			} else if current.LLM.Enabled || current.LLM.InvoiceExtractionEnabled() || current.LLM.Provider != "openai" || current.LLM.Model != "" || current.LLM.BaseURL != "" {
				t.Fatal("native consent survived upgrade", current.LLM)
			}
			var count int
			if err := f.connection.QueryRow(ctx, `SELECT count(*) FROM document_reindex_batches`).Scan(&count); err != nil || count != 1 {
				t.Fatal("duplicate migration batch", count, err)
			}
			var fingerprint string
			if err := f.connection.QueryRow(ctx, `SELECT document_pipeline_fingerprint(configuration) FROM document_processing_configurations WHERE revision=$1`, legacy.Revision).Scan(&fingerprint); err != nil || fingerprint != legacy.Fingerprint {
				t.Fatal("retained snapshot was changed", fingerprint, err)
			}
		})
	}
}

func TestRetainedSchedulersDoNotInheritCurrentContext(t *testing.T) {
	for _, pipeline := range []string{"reindex", "ai"} {
		t.Run(pipeline, func(t *testing.T) {
			f := newIngestionFixture(t)
			llmSource(t, f)
			ctx := t.Context()
			doc := f.accept(t, f.actor, strings.Repeat("9", 64), "Retained context work")
			f.ready(t, doc, "Retained pipeline snapshot", unitVector(0))
			legacy, err := f.service.GetProcessingConfiguration(ctx, f.actor)
			if err != nil {
				t.Fatal(err)
			}
			legacy.LLM.ContextLength = 0
			legacy.Fingerprint, err = legacy.CanonicalFingerprint()
			if err != nil {
				t.Fatal(err)
			}
			encoded, err := json.Marshal(legacy)
			if err != nil {
				t.Fatal(err)
			}
			f.exec(t, `UPDATE document_processing_configurations SET configuration=$1::jsonb #- '{LLM,ContextLength}',fingerprint=$2 WHERE revision=$3`, encoded, legacy.Fingerprint, legacy.Revision)
			current, err := f.service.SetProcessingConfiguration(ctx, f.actor, m.DocumentProcessingConfiguration{Language: legacy.Language, Segmentation: legacy.Segmentation, ExpectedRevision: &legacy.Revision, LLMUpdate: &m.DocumentLLMConfigurationUpdate{Provider: "openai", Model: "fixture", BaseURL: "https://provider.test/v1", ContextLength: new(65536)}})
			if err != nil {
				t.Fatal(err)
			}
			if current.LLM.ContextLength != 65536 || current.Revision == legacy.Revision {
				t.Fatal("current configuration fixture did not change")
			}
			var snapshot []byte
			if pipeline == "reindex" {
				batch := issue12Batch(t, f, f.actor, true)
				f.exec(t, `UPDATE document_reindex_batches SET configuration_revision=$2,configuration_fingerprint=$3 WHERE id=$1`, batch.ID, legacy.Revision, legacy.Fingerprint)
				issue12Maintain(t, f, 2)
				leases, err := f.service.Claim(ctx, 1, 30*time.Second, "retained-context")
				if err != nil || len(leases) != 1 {
					t.Fatalf("retained batch admission: %+v %v", leases, err)
				}
				if err := f.connection.QueryRow(ctx, `SELECT configuration FROM document_processing WHERE document_id=$1`, doc.ID).Scan(&snapshot); err != nil {
					t.Fatal(err)
				}
			} else {
				f.exec(t, `UPDATE document_processing_configuration SET ai_reschedule_revision=$1,ai_reschedule_cutoff=nextval('document_processing_event_seq'),ai_reschedule_cursor=0 WHERE id`, legacy.Revision)
				if err := f.service.MaintainProcessing(ctx); err != nil {
					t.Fatal(err)
				}
				if err := f.connection.QueryRow(ctx, `SELECT configuration FROM document_ai_jobs WHERE document_id=$1 ORDER BY attempt DESC LIMIT 1`, doc.ID).Scan(&snapshot); err != nil {
					t.Fatal(err)
				}
			}
			var accepted m.DocumentProcessingConfiguration
			if err := json.Unmarshal(snapshot, &accepted); err != nil {
				t.Fatal(err)
			}
			fingerprint, err := accepted.CanonicalFingerprint()
			if err != nil || accepted.LLM.ContextLength != 0 || accepted.LLM.RequestedContextLength() != 16384 || accepted.Fingerprint != legacy.Fingerprint || fingerprint != legacy.Fingerprint {
				t.Fatalf("retained snapshot inherited current settings: context=%d stored=%s actual=%s old=%s error=%v", accepted.LLM.ContextLength, accepted.Fingerprint, fingerprint, legacy.Fingerprint, err)
			}
		})
	}
}

func TestDocumentContextFingerprintMatchesSQLForLegacyAndExplicitValues(t *testing.T) {
	f := newIngestionFixture(t)
	for _, contextLength := range []int{0, 16384, 32768, 65536} {
		for _, enabled := range []bool{false, true} {
			for _, invoices := range []bool{false, true} {
				for _, external := range []bool{false, true} {
					configuration := m.DefaultConfiguration()
					configuration.LLM = m.DocumentLLMConfiguration{ContextLength: contextLength, Enabled: enabled, InvoiceEnabled: &invoices}
					if external {
						configuration.LLM.Provider, configuration.LLM.Model, configuration.LLM.BaseURL = "openai", "model", "https://example.test/v1"
					}
					want, err := configuration.CanonicalFingerprint()
					if err != nil {
						t.Fatal(err)
					}
					body, err := json.Marshal(configuration)
					if err != nil {
						t.Fatal(err)
					}
					var got string
					if err := f.connection.QueryRow(t.Context(), `SELECT document_pipeline_fingerprint($1::jsonb)`, body).Scan(&got); err != nil || got != want {
						t.Fatalf("SQL context fingerprint drift for %+v: %s %s %v", configuration.LLM, got, want, err)
					}
				}
			}
		}
	}
}
