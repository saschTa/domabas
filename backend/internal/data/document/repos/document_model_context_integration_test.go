//go:build integration

package repos_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestDocumentContextDefaultsUpdatesAndRetainedAdoption(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	ctx := t.Context()
	current, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil || current.LLM.ContextLength != 32768 || current.LLM.Defaults().Model != "qwen3.5:4b" {
		t.Fatalf("new context default: %+v %v", current.LLM, err)
	}
	legacy := current
	legacy.LLM.Model = ""
	legacy.LLM.ContextLength = 0
	legacy.Fingerprint, err = legacy.CanonicalFingerprint()
	if err != nil {
		t.Fatal(err)
	}
	encoded, err := json.Marshal(legacy)
	if err != nil {
		t.Fatal(err)
	}
	f.exec(t, `UPDATE document_processing_configuration SET configuration=$1::jsonb #- '{LLM,ContextLength}',fingerprint=$2,automatic_batch_id=NULL,ai_reschedule_revision=NULL,ai_reschedule_cutoff=NULL WHERE id`, encoded, legacy.Fingerprint)
	f.exec(t, `UPDATE document_processing_configurations SET configuration=$1::jsonb #- '{LLM,ContextLength}',fingerprint=$2 WHERE revision=$3`, encoded, legacy.Fingerprint, legacy.Revision)
	if err := initializeDocumentSource(ctx, source); err != nil {
		t.Fatal(err)
	}
	adopted, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil || adopted.Revision != legacy.Revision+1 || adopted.LLM.ContextLength != 32768 || adopted.LLM.Defaults().Model != "gemma3:4b" || adopted.AutomaticBatchID != "" {
		t.Fatalf("context adoption: %+v %v", adopted, err)
	}
	var active, snapshotContext, reschedule int
	var batches int
	if err := f.connection.QueryRow(ctx, `SELECT llm_context_length,(configuration->'LLM'->>'ContextLength')::integer,ai_reschedule_revision,(SELECT count(*) FROM document_reindex_batches) FROM document_processing_configuration WHERE id`).Scan(&active, &snapshotContext, &reschedule, &batches); err != nil {
		t.Fatal(err)
	}
	if active != 32768 || snapshotContext != active || int64(reschedule) != adopted.Revision || batches != 0 {
		t.Fatalf("adoption storage or scheduling changed: %d %d %d %d", active, snapshotContext, reschedule, batches)
	}
	var retained []byte
	if err := f.connection.QueryRow(ctx, `SELECT configuration FROM document_processing_configurations WHERE revision=$1`, legacy.Revision).Scan(&retained); err != nil {
		t.Fatal(err)
	}
	var retainedConfiguration m.DocumentProcessingConfiguration
	if err := json.Unmarshal(retained, &retainedConfiguration); err != nil {
		t.Fatal(err)
	}
	if retainedConfiguration.LLM.ContextLength != 0 || retainedConfiguration.LLM.RequestedContextLength() != 16384 || retainedConfiguration.Fingerprint != legacy.Fingerprint {
		t.Fatal("historical configuration changed")
	}
	if err := initializeDocumentSource(ctx, source); err != nil {
		t.Fatal(err)
	}
	restarted, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil || restarted.Revision != adopted.Revision {
		t.Fatalf("repeated adoption: %+v %v", restarted, err)
	}
	update := m.DocumentLLMConfigurationUpdate{Provider: "ollama", Model: "qwen3.5:4b", ContextLength: new(65536)}
	input := m.DocumentProcessingConfiguration{Language: adopted.Language, Segmentation: adopted.Segmentation, ExpectedRevision: &adopted.Revision, LLMUpdate: &update}
	saved, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil || saved.LLM.ContextLength != 65536 || saved.Revision != adopted.Revision+1 || saved.AutomaticBatchID != "" {
		t.Fatalf("context update: %+v %v", saved, err)
	}
	update.ContextLength = nil
	input.ExpectedRevision = &saved.Revision
	unchanged, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil || unchanged.LLM.ContextLength != 65536 || unchanged.Revision != saved.Revision {
		t.Fatalf("old client omission: %+v %v", unchanged, err)
	}
	if err := f.connection.QueryRow(ctx, `SELECT count(*) FROM document_reindex_batches`).Scan(&batches); err != nil || batches != 0 {
		t.Fatalf("context update reindexed OCR: %d %v", batches, err)
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
			current, err := f.service.SetProcessingConfiguration(ctx, f.actor, m.DocumentProcessingConfiguration{Language: legacy.Language, Segmentation: legacy.Segmentation, ExpectedRevision: &legacy.Revision, LLMUpdate: &m.DocumentLLMConfigurationUpdate{Provider: "ollama", Model: "qwen3.5:4b", ContextLength: new(65536)}})
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
