package repos

import (
	"context"
	"errors"
	"io"
	"math"
	"reflect"
	"strings"
	"testing"

	r "github.com/domabas/domabas/backend/internal/data/paperless/models"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type mockSource struct {
	PaperlessSource
	page      r.PaperlessPageRecord
	requested int
}

type paperlessOriginalSource struct {
	PaperlessSource
	document    r.PaperlessDocumentRecord
	names       map[string]string
	documentErr error
	nameErr     error
	downloadErr error
	nameCalls   int
	downloads   int
}

func (s *paperlessOriginalSource) Document(context.Context, m.PaperlessConnection, int64) (r.PaperlessDocumentRecord, error) {
	return s.document, s.documentErr
}

func (s *paperlessOriginalSource) Name(_ context.Context, _ m.PaperlessConnection, collection string, _ int64) (string, error) {
	s.nameCalls++
	return s.names[collection], s.nameErr
}

func (s *paperlessOriginalSource) Download(context.Context, m.PaperlessConnection, int64) (io.ReadCloser, error) {
	s.downloads++
	if s.downloadErr != nil {
		return nil, s.downloadErr
	}
	return io.NopCloser(strings.NewReader("original bytes")), nil
}

func TestPaperlessOriginalFallsBackForInvalidMetadata(t *testing.T) {
	for _, test := range []struct {
		name      string
		change    func(*paperlessOriginalSource)
		skipNames bool
	}{
		{"too many tags", func(s *paperlessOriginalSource) { s.document.Tags = make([]int64, 21) }, true},
		{"long title", func(s *paperlessOriginalSource) { s.document.Title = strings.Repeat("世", 201) }, true},
		{"blank title", func(s *paperlessOriginalSource) { s.document.Title = " \t " }, true},
		{"title control", func(s *paperlessOriginalSource) { s.document.Title = "Title\nline" }, true},
		{"invalid UTF-8", func(s *paperlessOriginalSource) { s.document.Title = string([]byte{0xff}) }, true},
		{"invalid date", func(s *paperlessOriginalSource) { s.document.Created = "2026-02-30" }, true},
		{"datetime", func(s *paperlessOriginalSource) { s.document.Created = "2026-09-23T12:00:00Z" }, true},
		{"long tag", func(s *paperlessOriginalSource) { s.names["tags"] = strings.Repeat("世", 65) }, false},
		{"empty tag", func(s *paperlessOriginalSource) { s.names["tags"] = " " }, false},
		{"tag control", func(s *paperlessOriginalSource) { s.names["tags"] = "Tax\n2026" }, false},
		{"long sender", func(s *paperlessOriginalSource) { s.names["correspondents"] = strings.Repeat("世", 321) }, false},
		{"sender control", func(s *paperlessOriginalSource) { s.names["correspondents"] = "Utility\x00" }, false},
		{"long description", func(s *paperlessOriginalSource) { s.names["document_types"] = strings.Repeat("世", 4000) }, false},
		{"description NUL", func(s *paperlessOriginalSource) { s.names["document_types"] = "Invoice\x00" }, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			correspondent, documentType, serial := int64(11), int64(12), int64(42)
			source := &paperlessOriginalSource{
				document: r.PaperlessDocumentRecord{ID: 7, Title: "Invoice", Created: "2026-09-23", Filename: "invoice.pdf", Tags: []int64{10}, Correspondent: &correspondent, DocumentType: &documentType, ArchiveSerialNumber: &serial},
				names:    map[string]string{"tags": "Finance", "correspondents": "Utility", "document_types": "Invoice"},
			}
			test.change(source)
			original, err := NewPaperlessRepository(source).Original(t.Context(), m.PaperlessConnection{ServerURL: "https://example.test/paperless"}, 7)
			if err != nil {
				t.Fatal(err)
			}
			defer original.Reader.Close()
			want, err := (d.DocumentMetadata{Title: "Paperless document 7", Kind: "document", Description: "Imported from Paperless: https://example.test/paperless/documents/7/details"}).Normalize()
			if err != nil || !reflect.DeepEqual(original.Metadata, want) {
				t.Fatalf("fallback metadata: %+v, error: %v", original.Metadata, err)
			}
			body, err := io.ReadAll(original.Reader)
			if err != nil || string(body) != "original bytes" || source.downloads != 1 || original.Filename != "invoice.pdf" {
				t.Fatal("original was not preserved", original.Filename, source.downloads, err)
			}
			if test.skipNames && source.nameCalls != 0 {
				t.Fatal("unnecessary metadata lookups after fallback", source.nameCalls)
			}
		})
	}
}

func TestPaperlessOriginalPreservesValidMetadata(t *testing.T) {
	correspondent, documentType, serial := int64(11), int64(12), int64(42)
	source := &paperlessOriginalSource{
		document: r.PaperlessDocumentRecord{ID: 7, Title: strings.Repeat("世", 200), Created: "2024-02-29", Tags: []int64{10, 10}, Correspondent: &correspondent, DocumentType: &documentType, ArchiveSerialNumber: &serial},
		names:    map[string]string{"tags": " " + strings.Repeat("A", 64) + " ", "correspondents": strings.Repeat("世", 320), "document_types": "Invoice"},
	}
	original, err := NewPaperlessRepository(source).Original(t.Context(), m.PaperlessConnection{ServerURL: "https://example.test"}, 7)
	if err != nil {
		t.Fatal(err)
	}
	defer original.Reader.Close()
	want, err := (d.DocumentMetadata{Title: source.document.Title, Kind: "document", DocumentDate: "2024-02-29", Tags: []string{strings.Repeat("a", 64)}, Sender: source.names["correspondents"], Description: "Imported from Paperless: https://example.test/documents/7/details\nDocument type: Invoice\nArchive serial number: 42"}).Normalize()
	if err != nil || !reflect.DeepEqual(original.Metadata, want) || original.Filename != "paperless-7" {
		t.Fatal("valid metadata changed", original, err)
	}
}

func TestPaperlessOriginalDoesNotIgnoreSourceFailures(t *testing.T) {
	for _, code := range []string{"source_unauthorized", "source_unavailable", "source_not_found", "source_incompatible"} {
		for _, stage := range []string{"document", "name", "download"} {
			t.Run(code+"/"+stage, func(t *testing.T) {
				failure := m.PaperlessFailure{Code: code}
				source := &paperlessOriginalSource{document: r.PaperlessDocumentRecord{ID: 7, Title: "Invoice", Tags: []int64{10}}, names: map[string]string{"tags": "Finance"}}
				switch stage {
				case "document":
					source.documentErr = failure
				case "name":
					source.nameErr = failure
				case "download":
					source.downloadErr = failure
					source.document.Title = ""
				}
				_, err := NewPaperlessRepository(source).Original(t.Context(), m.PaperlessConnection{ServerURL: "https://example.test"}, 7)
				if !errors.Is(err, failure) || (stage != "download" && source.downloads != 0) {
					t.Fatal("source failure ignored", err, source.downloads)
				}
			})
		}
	}
}

func TestPaperlessOriginalRejectsMismatchedIdentityAndInvalidFallback(t *testing.T) {
	for _, test := range []struct {
		name   string
		id     int64
		server string
	}{
		{"mismatched identity", 8, "https://example.test"},
		{"invalid fallback link", 7, "https://example.test/\x00"},
	} {
		t.Run(test.name, func(t *testing.T) {
			source := &paperlessOriginalSource{document: r.PaperlessDocumentRecord{ID: test.id}}
			_, err := NewPaperlessRepository(source).Original(t.Context(), m.PaperlessConnection{ServerURL: test.server}, 7)
			if !errors.Is(err, m.PaperlessFailure{Code: "invalid_metadata"}) || source.downloads != 0 {
				t.Fatal("invalid fallback accepted", err, source.downloads)
			}
		})
	}
}

func TestPaperlessDiscoveryKeepsDocumentsWithInvalidTitles(t *testing.T) {
	for _, title := range []string{strings.Repeat("世", 1025), "Title\x00", string([]byte{0xff})} {
		count := 1
		source := &mockSource{page: r.PaperlessPageRecord{Count: &count, Results: []r.PaperlessDocumentRecord{{ID: 7, Title: title}}}}
		page, err := NewPaperlessRepository(source).Preview(t.Context(), m.PaperlessConnection{}, 1)
		if err != nil || len(page.Items) != 1 || page.Items[0].ID != 7 || page.Items[0].Title != "Paperless document 7" {
			t.Fatal("metadata prevented discovery", page, err)
		}
		source.page.Results = append(source.page.Results, r.PaperlessDocumentRecord{ID: 7})
		if _, err := NewPaperlessRepository(source).Preview(t.Context(), m.PaperlessConnection{}, 1); err == nil {
			t.Fatal("inconsistent discovery IDs accepted")
		}
	}
}

func (s *mockSource) Page(_ context.Context, _ m.PaperlessConnection, page int) (r.PaperlessPageRecord, error) {
	s.requested = page
	return s.page, nil
}

func TestDiscoveryAcceptsLargeLibrariesAndLatePages(t *testing.T) {
	count := 10001
	source := &mockSource{page: r.PaperlessPageRecord{Count: &count, Results: []r.PaperlessDocumentRecord{{ID: 10001, Title: "Late page document"}}}}
	page, err := NewPaperlessRepository(source).Preview(t.Context(), m.PaperlessConnection{}, 101)
	if err != nil || page.Total != count || len(page.Items) != 1 || source.requested != 101 {
		t.Fatal("large source or late page rejected", page, source.requested, err)
	}
	count = math.MaxInt32
	if _, err := NewPaperlessRepository(source).Preview(t.Context(), m.PaperlessConnection{}, 20000000); err != nil {
		t.Fatal("valid source total rejected", err)
	}
	count++
	if _, err := NewPaperlessRepository(source).Preview(t.Context(), m.PaperlessConnection{}, 1); err == nil {
		t.Fatal("unrepresentable source total accepted")
	}
	count = 10001
	source.page.Results = make([]r.PaperlessDocumentRecord, m.PageSize+1)
	if _, err := NewPaperlessRepository(source).Preview(t.Context(), m.PaperlessConnection{}, 1); err == nil {
		t.Fatal("page response exceeded its bound")
	}
}
