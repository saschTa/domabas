//go:build integration

package repos_test

import (
	"strings"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestStagedUploadRetirementRequiresDurableReadyDocument(t *testing.T) {
	f := newIngestionFixture(t)
	type candidate struct {
		location, state string
		eligible        bool
	}
	candidates := []candidate{{"staged", "queued", false}, {"final", "queued", false}, {"unlocked", "processing", false}, {"final", "ready", true}, {"unlocked", "ready", true}, {"staged", "ready", false}}
	expected := map[string]bool{}
	for i, candidate := range candidates {
		document := f.accept(t, f.actor, strings.Repeat(string(rune('a'+i)), 64), "retained original")
		f.exec(t, "UPDATE document_files SET location=$2 WHERE document_id=$1", document.ID, candidate.location)
		f.exec(t, "UPDATE document_processing SET state=$2 WHERE document_id=$1", document.ID, candidate.state)
		expected[document.ID] = candidate.eligible
	}
	policy := m.DocumentStagedUploadRetention()
	refs, err := f.repository.Reap(t.Context(), policy)
	if err != nil || len(refs) != 2 {
		t.Fatalf("retirement candidates: %+v %v", refs, err)
	}
	for _, ref := range refs {
		if !expected[ref.DocumentID] || ref.Location != "staged" {
			t.Fatalf("unsafe original selected: %+v", ref)
		}
	}
	ref := refs[0]
	f.exec(t, "UPDATE document_processing SET state='processing' WHERE document_id=$1", ref.DocumentID)
	if err = f.repository.Reaped(t.Context(), ref, policy); err != nil {
		t.Fatal(err)
	}
	var retained bool
	if err = f.connection.QueryRow(t.Context(), "SELECT EXISTS(SELECT 1 FROM document_uploads WHERE id=$1)", ref.DocumentID).Scan(&retained); err != nil || !retained {
		t.Fatalf("retirement acknowledgement ignored current readiness: %v %v", retained, err)
	}
	f.exec(t, "UPDATE document_processing SET state='ready' WHERE document_id=$1", ref.DocumentID)
	if err = f.repository.Reaped(t.Context(), ref, policy); err != nil {
		t.Fatal(err)
	}
	if err = f.connection.QueryRow(t.Context(), "SELECT EXISTS(SELECT 1 FROM document_uploads WHERE id=$1)", ref.DocumentID).Scan(&retained); err != nil || retained {
		t.Fatalf("ready original was not retired: %v %v", retained, err)
	}
	if _, err = f.repository.Reference(t.Context(), f.actor, ref.DocumentID); err != nil {
		t.Fatalf("retirement removed durable file reference: %v", err)
	}
}
