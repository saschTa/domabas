//go:build integration

package postgres

import (
	"fmt"
	"testing"
	"testing/fstest"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
)

func TestDocumentJobsMigrationPreservesLegacyExtractionAndUnknownStartEvidence(t *testing.T) {
	source := migrationSource(t, testdb.New(t))
	files := fstest.MapFS{}
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.Name() >= "007" {
			continue
		}
		name := "migrations/" + entry.Name()
		contents, err := migrations.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		files[name] = &fstest.MapFile{Data: contents}
	}
	if err := source.migrate(t.Context(), files); err != nil {
		t.Fatal(err)
	}
	account := uuid.New()
	migrationSQL(t, source, "INSERT INTO accounts(id,name) VALUES($1,'Retained ingestion library')", account)
	stamp := time.Date(2020, 2, 3, 4, 5, 6, 0, time.UTC)
	snapshot := `{"Revision":4,"Language":"deu","Segmentation":"single_block","Engine":"tesseract","EngineVersion":"5.5.3","EmbeddingModel":"nomic-embed-text:v1.5","EmbeddingDigest":"0a109f422b47e3a30ba2b10eca18548e944e8a23073ee3f3e947efcf3c45e59f","Dimensions":768,"Weights":[]}`
	type retained struct {
		id            uuid.UUID
		state, stage  string
		manual        *string
		knownRun      bool
		ambiguous     bool
		machineProven bool
	}
	manual := "Exact corrected text"
	items := []retained{
		{uuid.New(), "processing", "embedding", &manual, true, false, false},
		{uuid.New(), "ready", "complete", &manual, false, false, false},
		{uuid.New(), "ready", "complete", nil, true, false, true},
		{uuid.New(), "queued", "queued", nil, false, false, false},
		{uuid.New(), "queued", "queued", nil, false, true, false},
	}
	for _, item := range items {
		migrationSQL(t, source, `INSERT INTO documents(id,account_id,title,description,created_at,ocr_machine_text,ocr_manual_text,ocr_revision) VALUES($1,$2,'Retained title','Retained description',$3,'Exact machine text',$4,7)`, item.id, account, stamp, item.manual)
		workflow, run := "", ""
		if item.knownRun {
			workflow, run = fmt.Sprintf("document-ingestion-v1/%s/%s/3", account, item.id), uuid.NewString()
		}
		migrationSQL(t, source, `INSERT INTO document_processing(document_id,account_id,generation,state,stage,configuration_revision,configuration,updated_at,delivery_deadline,workflow_id,run_id,ocr_revision) VALUES($1,$2,3,$3,$4,4,$5,$6,$6::timestamptz+interval '24 hours',$7,$8,7)`, item.id, account, item.state, item.stage, snapshot, stamp, workflow, run)
		if item.ambiguous {
			migrationSQL(t, source, `INSERT INTO document_outbox(id,account_id,document_id,generation,configuration_revision,delivery_deadline,lease_token,lease_expires_at) VALUES($1,$2,$3,3,4,$4,$5,$4)`, uuid.New(), account, item.id, stamp, uuid.New())
		}
	}
	var cutover time.Time
	if err := source.pool.QueryRow(t.Context(), "SELECT clock_timestamp()").Scan(&cutover); err != nil {
		t.Fatal(err)
	}
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	for _, item := range items {
		var processingRequires, jobRequires bool
		var started, delivery *time.Time
		var machineFingerprint *string
		var machineText string
		var manualText *string
		var reason, fingerprint, language, extraction string
		var created time.Time
		var sequence, jobSequence int64
		err := source.pool.QueryRow(t.Context(), `SELECT p.requires_extraction,j.requires_extraction,j.started_at,p.delivery_deadline,d.machine_extraction_fingerprint,d.ocr_machine_text,d.ocr_manual_text,j.reason,j.configuration_fingerprint,p.configuration->>'Language',p.configuration->>'ExtractionRevision',d.created_at,d.accepted_sequence,j.generation_sequence FROM documents d JOIN document_processing p ON p.document_id=d.id JOIN document_processing_jobs j ON j.document_id=d.id WHERE d.id=$1`, item.id).Scan(&processingRequires, &jobRequires, &started, &delivery, &machineFingerprint, &machineText, &manualText, &reason, &fingerprint, &language, &extraction, &created, &sequence, &jobSequence)
		if err != nil {
			t.Fatal(err)
		}
		if processingRequires != (item.manual == nil) || jobRequires != processingRequires || started != nil {
			t.Fatalf("legacy correction or unknown start became invented evidence: requires=%t/%t started=%v", processingRequires, jobRequires, started)
		}
		if (machineFingerprint != nil) != item.machineProven || (machineFingerprint != nil && *machineFingerprint != fingerprint) {
			t.Fatalf("unsupported retained machine provenance: %v", machineFingerprint)
		}
		if machineText != "Exact machine text" || (manualText == nil) != (item.manual == nil) || (manualText != nil && *manualText != *item.manual) || !created.Equal(stamp) {
			t.Fatal("migration changed retained text or document creation time")
		}
		if reason != "legacy" || language != "deu" || extraction != "tesseract-pdf-image-v1" || sequence <= 0 || jobSequence <= sequence {
			t.Fatal("legacy snapshot or event ordering did not survive migration")
		}
		var executions int
		if err := source.pool.QueryRow(t.Context(), `SELECT count(*) FROM document_processing_executions WHERE document_id=$1 AND legacy AND closed_at IS NULL AND latest_permit_end >= $2 AND start_retry_until <= $2`, item.id, cutover).Scan(&executions); err != nil {
			t.Fatal(err)
		}
		expected := 0
		if item.knownRun || item.ambiguous {
			expected = 1
		}
		if executions != expected {
			t.Fatalf("legacy execution lost its conservative cutover horizon: got %d want %d", executions, expected)
		}
		if item.state == "queued" && !item.ambiguous && delivery != nil {
			t.Fatal("never-attempted waiting work retained a running delivery clock")
		}
	}
	migrationSQL(t, source, `UPDATE document_processing SET updated_at=clock_timestamp() WHERE document_id=$1`, items[0].id)
	var invented bool
	if err := source.pool.QueryRow(t.Context(), `SELECT started_at IS NOT NULL FROM document_processing_jobs WHERE document_id=$1`, items[0].id).Scan(&invented); err != nil || invented {
		t.Fatalf("later legacy metadata update invented an unknown start: %t %v", invented, err)
	}
}
