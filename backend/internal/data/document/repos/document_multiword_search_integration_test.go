//go:build integration

package repos_test

import (
	"encoding/json"
	"fmt"
	"slices"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestHybridSearchMultiwordManyDocuments(t *testing.T) {
	f := newIngestionFixture(t)
	configuration, err := json.Marshal(m.DefaultConfiguration())
	if err != nil {
		t.Fatal(err)
	}
	f.exec(t, `INSERT INTO documents(id,account_id,title,created_at) SELECT gen_random_uuid(),$1,'Service archive',clock_timestamp() FROM generate_series(1,1536)`, f.actor.AccountID)
	f.exec(t, `INSERT INTO document_processing(document_id,account_id,generation,state,stage,configuration_revision,configuration,updated_at,split_pipeline) SELECT id,account_id,1,'ready','complete',1,$2,clock_timestamp(),false FROM documents WHERE account_id=$1`, f.actor.AccountID, configuration)
	f.exec(t, `INSERT INTO document_chunks(account_id,document_id,generation,position,content,embedding,model_digest) SELECT d.account_id,d.id,1,g,$2||' '||g,$3,$4 FROM documents d CROSS JOIN generate_series(0,11) g WHERE d.account_id=$1`, f.actor.AccountID, multiwordSearchContent, unitVector(1), m.EmbeddingDigest)
	f.exec(t, `ANALYZE documents; ANALYZE document_chunks; ANALYZE document_processing`)
	for _, query := range []string{"invoice", "invoice payments", "invioce payment"} {
		t.Run(query, func(t *testing.T) {
			input := m.DocumentSearchInput{Mode: "hybrid", Query: query, Space: m.DefaultConfiguration().EmbeddingSpace(), Limit: 20}
			seen := map[string]bool{}
			for range 2 {
				started := time.Now()
				page, err := f.search(t.Context(), f.actor, input, unitVector(0))
				t.Logf("1536 documents with 12 chunks each: %s; %d results; error: %v", time.Since(started), len(page.Items), err)
				if err != nil || len(page.Items) != 20 || page.NextCursor == "" || page.Total != nil {
					t.Fatalf("multiword search page: %+v %v", page, err)
				}
				for _, item := range page.Items {
					if seen[item.Document.ID] || item.Score < m.DocumentContentScorePriority+m.DocumentFuzzyScoreMinimum {
						t.Fatalf("repeated or missing lexical match: %+v", item)
					}
					seen[item.Document.ID] = true
				}
				input.Cursor = page.NextCursor
			}
		})
	}
}

func TestHybridSearchMultiwordRealisticChunks(t *testing.T) {
	f := newIngestionFixture(t)
	content := multiwordSearchContent
	var expectedIDs []string
	for index := range 16 {
		doc := f.accept(t, f.actor, fmt.Sprintf("%064x", index+1), "Service archive")
		expectedIDs = append(expectedIDs, doc.ID)
		f.ready(t, doc, content, unitVector(1))
		f.exec(t, `INSERT INTO document_chunks(account_id,document_id,generation,position,content,embedding,model_digest) SELECT $1,$2,1,g,$3||' '||g,$4,$5 FROM generate_series(1,1023) g`, f.actor.AccountID, doc.ID, content, unitVector(1), m.EmbeddingDigest)
	}
	f.exec(t, `ANALYZE documents; ANALYZE document_chunks; ANALYZE document_processing`)
	slices.Sort(expectedIDs)
	for _, test := range []struct {
		query string
		match bool
	}{
		{"invoice", true},
		{"invoice payment", true},
		{"invoice payments", true},
		{"invioce payment", true},
		{"invoice missing", false},
	} {
		t.Run(test.query, func(t *testing.T) {
			started := time.Now()
			result, err := f.search(t.Context(), f.actor, m.DocumentSearchInput{Mode: "hybrid", Query: test.query, Space: m.DefaultConfiguration().EmbeddingSpace()}, unitVector(0))
			t.Logf("16384 chunks, %d bytes each: %s; %d results; error: %v", len(content), time.Since(started), len(result.Items), err)
			if err != nil {
				t.Fatal(err)
			}
			var ids []string
			for _, item := range result.Items {
				ids = append(ids, item.Document.ID)
				if item.Score < m.DocumentContentScorePriority+m.DocumentFuzzyScoreMinimum || item.Score >= m.DocumentMetadataScorePriority {
					t.Fatalf("expected content match, got score %f", item.Score)
				}
			}
			slices.Sort(ids)
			if result.Total != nil || result.NextCursor != "" || (test.match && !slices.Equal(ids, expectedIDs)) || (!test.match && len(ids) != 0) {
				t.Fatalf("multiword lexical results: %+v", result)
			}
		})
	}
}

const multiwordSearchContent = `Invoice payment details for annual maintenance services. The customer receives a complete statement showing materials, labour, equipment, delivery, installation, inspection, replacement, repairs, transport, insurance, accounting, administration and support. Please transfer the outstanding balance using the reference number before the specified date. This agreement covers heating, plumbing, electrical systems, ventilation, windows, doors, floors, walls, roofing, drainage, cleaning, security, lighting, painting, garden work and waste disposal. The contractor confirms that all scheduled visits were completed according to the attached checklist. Separate charges apply for emergency attendance, additional components, specialist advice, travel expenses, storage, packaging, testing, certification and documentation. Contact our office during business hours to discuss questions concerning your account, address, telephone, correspondence, bank information, taxes, discounts, deposits, credits, refunds, corrections, purchase orders or warranty. Retain this document with your financial records. The building manager approved the completed tasks after reviewing photographs, measurements, reports, schedules, safety instructions, technical specifications and supplier statements. Future appointments require written confirmation from the property owner. Residents should report damage promptly and provide access to affected rooms. Materials remain subject to availability and manufacturer conditions. Prices include ordinary preparation and disposal costs. A revised quotation is required when circumstances change substantially. All records are available for inspection on request.`
