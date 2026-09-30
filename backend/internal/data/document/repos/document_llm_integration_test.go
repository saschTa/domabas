//go:build integration

package repos_test

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	sources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/domabas/domabas/backend/internal/data/document/repos"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func llmSource(t *testing.T, f *ingestionFixture, limits ...r.DocumentIngestionLimits) *sources.DocumentDataSource {
	t.Helper()
	vault, err := sources.CredentialVault(base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32)))
	if err != nil {
		t.Fatal(err)
	}
	f.resourceCapacity(t, 1)
	if len(limits) > 0 {
		f.resourceCapacity(t, max(1, limits[0].Concurrency, limits[0].AIConcurrency))
	}
	s := sources.NewDocumentLLMDataSource(f.source.Database(), fixturePublication{}, "", vault, f.scheduler, limits...)
	if err = initializeDocumentSource(t.Context(), s); err != nil {
		t.Fatal(err)
	}
	f.setRepository(repos.NewDocumentIngestionRepository(s))
	return s
}

func TestLLMSettingsEncryptedRevisionedAndRetained(t *testing.T) {
	f := newIngestionFixture(t)
	s := llmSource(t, f)
	ctx := t.Context()
	initial, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil || initial.LLM.Enabled {
		t.Fatal(initial, err)
	}
	key := "provider-secret-unique"
	update := m.DocumentLLMConfigurationUpdate{Enabled: true, Provider: "openai", Model: "fixture", BaseURL: "https://example.test/v1", APIKey: &key}
	input := m.DocumentProcessingConfiguration{Language: "eng+deu", Segmentation: "auto", ExpectedRevision: &initial.Revision, LLMUpdate: &update}
	c, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil {
		t.Fatal(err)
	}
	if c.Revision != initial.Revision+1 || c.AutomaticBatchID != "" || c.LLM.CredentialID == "" {
		t.Fatal("missing revision or encrypted credential reference", c)
	}
	var reschedule int64
	if err = f.connection.QueryRow(ctx, "SELECT ai_reschedule_revision FROM document_processing_configuration WHERE id").Scan(&reschedule); err != nil || reschedule != c.Revision {
		t.Fatal("AI rescheduling intent missing", reschedule, err)
	}
	var snapshot string
	var encrypted []byte
	if err = f.connection.QueryRow(ctx, "SELECT configuration::text FROM document_processing_configuration WHERE id").Scan(&snapshot); err != nil {
		t.Fatal(err)
	}
	if err = f.connection.QueryRow(ctx, "SELECT encrypted_key FROM document_llm_credentials WHERE id=$1", c.LLM.CredentialID).Scan(&encrypted); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(snapshot, key) || bytes.Contains(encrypted, []byte(key)) {
		t.Fatal("plaintext credential persisted")
	}
	if got, err := s.PropertyCredential(ctx, c.LLM.CredentialID); err != nil || got != key {
		t.Fatal("credential cannot be decrypted", err)
	}
	if err = initializeDocumentSource(ctx, s); err != nil {
		t.Fatal(err)
	}
	retained, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil || !retained.LLM.Equal(c.LLM) || retained.Revision != c.Revision {
		t.Fatal("restart reset settings", retained, err)
	}
	input.ExpectedRevision = &c.Revision
	same, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil || same.Revision != c.Revision {
		t.Fatal("identical save changed revision", err)
	}
	update.APIKey = nil
	update.Model = "replacement"
	input.ExpectedRevision = &initial.Revision
	if _, err = f.service.SetProcessingConfiguration(ctx, f.actor, input); !errors.Is(err, m.ErrConflict) {
		t.Fatal("stale save accepted", err)
	}
	input.ExpectedRevision = &c.Revision
	replaced, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil || replaced.LLM.CredentialID != c.LLM.CredentialID {
		t.Fatal("omitted key was lost", err)
	}
	update.BaseURL = "https://another.test/v1"
	input.ExpectedRevision = &replaced.Revision
	moved, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil || moved.LLM.CredentialID != "" {
		t.Fatal("credential crossed endpoint", err)
	}
	if old, err := s.PropertyCredential(ctx, c.LLM.CredentialID); err != nil || old != key {
		t.Fatal("old generation credential was destroyed", err)
	}
	update.APIKey = &key
	input.ExpectedRevision = &moved.Revision
	withKey, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil {
		t.Fatal(err)
	}
	update.APIKey = nil
	update.ClearAPIKey = true
	input.ExpectedRevision = &withKey.Revision
	cleared, err := f.service.SetProcessingConfiguration(ctx, f.actor, input)
	if err != nil || cleared.LLM.CredentialID != "" {
		t.Fatal("key not cleared", err)
	}
	other := f.addActor(t)
	f.exec(t, "UPDATE users SET system_role='user' WHERE id=$1", other.UserID)
	if _, err = f.service.GetProcessingConfiguration(ctx, other); !errors.Is(err, m.ErrForbidden) {
		t.Fatal("namespace owner read instance settings", err)
	}
	if _, err = f.service.SetProcessingConfiguration(ctx, other, input); !errors.Is(err, m.ErrForbidden) {
		t.Fatal("namespace owner changed instance settings", err)
	}
	for _, llm := range []m.DocumentLLMConfiguration{{}, c.LLM, replaced.LLM, moved.LLM, cleared.LLM, {InvoiceEnabled: new(true)}, {InvoiceEnabled: new(false)}, {Enabled: true, InvoiceEnabled: new(true)}, {Enabled: true, InvoiceEnabled: new(false)}} {
		conf := m.DefaultConfiguration()
		conf.LLM = llm
		want, err := conf.CanonicalFingerprint()
		if err != nil {
			t.Fatal(err)
		}
		encoded, _ := json.Marshal(conf)
		var got string
		if err = f.connection.QueryRow(ctx, "SELECT document_pipeline_fingerprint($1::jsonb)", encoded).Scan(&got); err != nil || got != want {
			t.Fatalf("SQL identity drift: %s %s %v", got, want, err)
		}
	}
}

func TestInvoiceAISwitchIsIndependentAndPreservedWhenOmitted(t *testing.T) {
	f := newIngestionFixture(t)
	s := llmSource(t, f)
	current, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
	if err != nil || current.LLM.Enabled || current.LLM.InvoiceExtractionEnabled() {
		t.Fatal("fresh AI settings are not off", err)
	}
	for _, choices := range [][2]bool{{true, false}, {false, true}, {true, true}, {false, false}} {
		input := m.DocumentProcessingConfiguration{Language: current.Language, Segmentation: current.Segmentation, ExpectedRevision: &current.Revision, LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: choices[0], InvoiceEnabled: new(choices[1]), Provider: "ollama", Model: "qwen3.5:4b"}}
		next, err := f.service.SetProcessingConfiguration(t.Context(), f.actor, input)
		if err != nil || next.Revision != current.Revision+1 || next.LLM.Enabled != choices[0] || next.LLM.InvoiceExtractionEnabled() != choices[1] || next.AutomaticBatchID != "" {
			t.Fatalf("independent switch update failed: %+v %v", next, err)
		}
		if err = initializeDocumentSource(t.Context(), s); err != nil {
			t.Fatal(err)
		}
		retained, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
		if err != nil || !retained.LLM.Equal(next.LLM) || retained.Revision != next.Revision {
			t.Fatal("restart changed independent settings", err)
		}
		input.ExpectedRevision = &next.Revision
		input.LLMUpdate.InvoiceEnabled = nil
		omitted, err := f.service.SetProcessingConfiguration(t.Context(), f.actor, input)
		if err != nil || omitted.Revision != next.Revision || omitted.LLM.InvoiceExtractionEnabled() != choices[1] {
			t.Fatal("older client changed invoice switch or scheduled a no-op reindex", err)
		}
		current = next
	}
}

func TestLLMPropertiesPreserveMetadataAndFenceGenerations(t *testing.T) {
	f := newIngestionFixture(t)
	s := llmSource(t, f)
	f.resourceCapacity(t, 4)
	ctx := t.Context()
	_, err := f.service.SetProcessingConfiguration(ctx, f.actor, m.DocumentProcessingConfiguration{Language: "eng+deu", Segmentation: "auto", LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: true, Provider: "ollama", Model: "qwen3.5:4b"}})
	if err != nil {
		t.Fatal(err)
	}
	properties := repos.NewDocumentPropertyRepository(s)
	for i, scenario := range []string{"fill missing", "preserve populated", "preserve concurrent clearing", "stale generation"} {
		t.Run(scenario, func(t *testing.T) {
			doc := f.accept(t, f.actor, strings.Repeat(string(rune('a'+i)), 64), "User title")
			if i == 1 {
				existing := "User description"
				tags := []string{"user-tag"}
				if _, err := f.service.Update(ctx, f.actor, doc.ID, m.DocumentMetadataPatch{Description: &existing, Tags: &tags}); err != nil {
					t.Fatal(err)
				}
			}
			job := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
			f.admit(t, job)
			work, err := f.service.Work(ctx, job, "extracting")
			if err != nil {
				t.Fatal(err)
			}
			if err = f.service.SaveExtraction(ctx, job, work.Revision, "Invoice OCR content"); err != nil {
				t.Fatal(err)
			}
			w, err := properties.Work(ctx, job)
			if err != nil || w.Stage != "enriching" || w.Text != "Invoice OCR content" {
				t.Fatal(w, err)
			}
			if i == 2 {
				empty := ""
				if _, err = f.service.Update(ctx, f.actor, doc.ID, m.DocumentMetadataPatch{Description: &empty}); err != nil {
					t.Fatal(err)
				}
			}
			if i == 3 {
				if err = f.repository.Fail(ctx, job, "processing_failed"); err != nil {
					t.Fatal(err)
				}
				if _, err = f.service.Retry(ctx, f.actor, doc.ID); err != nil {
					t.Fatal(err)
				}
			}
			values := m.DocumentMetadata{Description: "AI description", Tags: []string{"ai-tag"}, Sender: "AI sender", Subject: "AI subject", DocumentDate: "2026-09-19"}
			w.NextStage = "embedding"
			err = properties.Save(ctx, w, w.Metadata.FillExtractedProperties(values))
			if i == 3 {
				if !errors.Is(err, m.ErrStaleJob) {
					t.Fatal("stale properties published", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if err = properties.Save(ctx, w, values); err != nil {
				t.Fatal("replay failed", err)
			}
			var title, description, sender string
			var tags []string
			if err = f.connection.QueryRow(ctx, "SELECT title,description,sender,tags FROM documents WHERE id=$1", doc.ID).Scan(&title, &description, &sender, &tags); err != nil {
				t.Fatal(err)
			}
			if title != "User title" {
				t.Fatal("user title replaced")
			}
			switch i {
			case 0:
				if description != "AI description" || sender != "AI sender" {
					t.Fatal("properties not filled")
				}
			case 1:
				if description != "User description" || len(tags) != 1 || tags[0] != "user-tag" || sender != "AI sender" {
					t.Fatal("existing metadata overwritten")
				}
			case 2:
				if description != "" || sender != "" {
					t.Fatal("concurrent metadata edit overwritten")
				}
			}
		})
	}
}

func TestLLMAutomaticKeySurvivesRestartAndFailsClosed(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	path := filepath.Join(t.TempDir(), "keys", "llm.key")
	key, err := sources.CredentialKey(ctx, f.source.Database(), "", path)
	if err != nil {
		t.Fatal(err)
	}
	if again, err := sources.CredentialKey(ctx, f.source.Database(), "", path); err != nil || again != key {
		t.Fatal("key not retained", err)
	}
	vault, err := sources.CredentialVault(key)
	if err != nil {
		t.Fatal(err)
	}
	s := sources.NewDocumentLLMDataSource(f.source.Database(), fixturePublication{}, "", vault, f.scheduler)
	if err = initializeDocumentSource(ctx, s); err != nil {
		t.Fatal(err)
	}
	token := "encrypted-token"
	f.setRepository(repos.NewDocumentIngestionRepository(s))
	_, err = f.service.SetProcessingConfiguration(ctx, f.actor, m.DocumentProcessingConfiguration{Language: "eng", Segmentation: "auto", LLMUpdate: &m.DocumentLLMConfigurationUpdate{Provider: "openai", Model: "fixture", BaseURL: "https://example.test/v1", APIKey: &token}})
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if _, err = sources.CredentialKey(ctx, f.source.Database(), "", path); err == nil {
		t.Fatal("missing retained key was silently regenerated")
	}
	wrong := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{9}, 32))
	if _, err = sources.CredentialKey(ctx, f.source.Database(), wrong, path); err == nil {
		t.Fatal("wrong key accepted")
	}
	if _, err = sources.CredentialKey(ctx, f.source.Database(), key, path); err != nil {
		t.Fatal("restored override cannot decrypt", err)
	}
}
