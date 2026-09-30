package models

import (
	"errors"
	"math"
	"testing"
	"time"
)

func processingWork() DocumentProcessingWork {
	return DocumentProcessingWork{Eligible: true, State: "processing", Stage: "extracting", Configuration: DefaultConfiguration(), Reference: DocumentFileReference{File: DocumentFile{MediaType: "application/pdf"}}}
}
func TestDocumentProcessingPlanPreservesReplayAndDeadlines(t *testing.T) {
	work := processingWork()
	work.State = "queued"
	work.Stage = "queued"
	command, err := PlanDocumentProcessing(work, "extracting")
	if err != nil || command.Stage != "extracting" || command.Deadline != 15*time.Minute || command.Unlimited {
		t.Fatalf("queued plan: %+v %v", command, err)
	}
	if _, err = PlanDocumentProcessing(work, "embedding"); !errors.Is(err, ErrStaleJob) {
		t.Fatalf("queued embed accepted: %v", err)
	}
	work.UnlimitedInference = true
	command, err = PlanDocumentProcessing(work, "extracting")
	if err != nil || !command.Unlimited {
		t.Fatalf("unlimited lost: %+v %v", command, err)
	}
	work.State = "ready"
	work.Stage = "complete"
	work.Eligible = false
	command, err = PlanDocumentProcessing(work, "finalizing")
	if err != nil || !command.Replay {
		t.Fatalf("publication replay: %+v %v", command, err)
	}
	if _, err = PlanDocumentProcessing(work, "extracting"); !errors.Is(err, ErrStaleJob) {
		t.Fatalf("ready extraction accepted: %v", err)
	}
}
func TestDocumentExtractionPlanKeepsManualAndSplitRouting(t *testing.T) {
	for _, split := range []bool{false, true} {
		work := processingWork()
		work.SplitPipeline = split
		work.Configuration.LLM.Enabled = true
		command, err := PlanDocumentExtraction(work, 0, DocumentExtraction{Text: "machine evidence"})
		want := "enriching"
		if split {
			want = "embedding"
		}
		if err != nil || command.Stage != want || command.Revision != 1 || len(command.Chunks) != 1 {
			t.Fatalf("split=%v %+v %v", split, command, err)
		}
		manual := ""
		work.ManualText = &manual
		work.Revision = 4
		command, err = PlanDocumentExtraction(work, 4, DocumentExtraction{Text: "machine evidence"})
		if err != nil || command.Stage != "finalizing" || command.Revision != 4 || len(command.Chunks) != 0 {
			t.Fatalf("empty manual replaced: %+v %v", command, err)
		}
		_, err = PlanDocumentExtraction(work, 4, DocumentExtraction{InvoiceFailureCode: "invalid_invoice"})
		if split && err != nil || !split && err == nil {
			t.Fatalf("split failure policy split=%v: %v", split, err)
		}
	}
	work := processingWork()
	work.Revision = math.MaxInt64
	if _, err := PlanDocumentExtraction(work, work.Revision, DocumentExtraction{}); err == nil {
		t.Fatal("revision overflow accepted")
	}
}
func TestDocumentEmbeddingAndPublicationPlansFenceFacts(t *testing.T) {
	work := processingWork()
	work.Stage = "embedding"
	work.Revision = 4
	vector := make([]float64, EmbeddingDimensions)
	vector[0] = 2
	chunks := []DocumentChunk{{Text: "evidence", Vector: vector}}
	command, err := PlanDocumentEmbeddings(work, 4, work.Configuration.EmbeddingSpace(), chunks)
	if err != nil || command.Chunks[0].Vector[0] != 1 || chunks[0].Vector[0] != 2 {
		t.Fatalf("normalization mutated input: %+v %v", command, err)
	}
	if _, err = PlanDocumentEmbeddings(work, 3, work.Configuration.EmbeddingSpace(), chunks); !errors.Is(err, ErrStaleJob) {
		t.Fatalf("stale revision accepted: %v", err)
	}
	space := work.Configuration.EmbeddingSpace()
	space.Digest = "changed"
	if _, err = PlanDocumentEmbeddings(work, 4, space, chunks); err == nil {
		t.Fatal("foreign embedding space accepted")
	}
	work.Stage = "finalizing"
	if _, err = PlanDocumentPublication(work, 4); !errors.Is(err, ErrStaleJob) {
		t.Fatalf("missing embeddings accepted: %v", err)
	}
	work.EmbeddingsComplete = true
	publication, err := PlanDocumentPublication(work, 4)
	if err != nil || publication.State != "ready" || publication.Stage != "complete" || publication.Digest != work.Configuration.EmbeddingDigest {
		t.Fatalf("publication plan: %+v %v", publication, err)
	}
}
