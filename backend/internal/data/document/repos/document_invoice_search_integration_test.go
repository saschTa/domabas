//go:build integration

package repos_test

import (
	"errors"
	source "github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	repos "github.com/domabas/domabas/backend/internal/data/invoice/repos"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	invoiceservices "github.com/domabas/domabas/backend/internal/domain/invoice/services"
	fixtures "github.com/domabas/domabas/backend/tests/fixtures/invoices"
	"strings"
	"testing"
)

func TestInvoiceSearchUsesOnlyInvoicePropertiesAndBoundCursors(t *testing.T) {
	f := newIngestionFixture(t)
	repository := invoiceservices.NewInvoiceService(repos.NewInvoiceRepository(source.NewInvoiceDataSource(f.source.Database())), nil, nil, f.authority, nil)
	ctx := t.Context()
	seed := func(hash, number, kind string) string {
		d := f.accept(t, f.actor, strings.Repeat(hash, 64), "HiddenDocumentTitleOnly")
		j := document.DocumentJob{AccountID: f.actor.AccountID, DocumentID: d.ID, Generation: 1}
		f.admit(t, j)
		w, err := f.service.Work(ctx, j, "extracting")
		if err != nil {
			t.Fatal(err)
		}
		xml := fixtures.CII
		if kind == "ai" {
			xml = nil
		}
		if err = f.service.SaveExtraction(ctx, j, w.Revision, "HiddenOcrOnly", xml); err != nil {
			t.Fatal(err)
		}
		work, err := repository.Work(ctx, j)
		if err != nil {
			t.Fatal(err)
		}
		v, err := source.ParseXML(ctx, fixtures.CII)
		if err != nil {
			t.Fatal(err)
		}
		v.Number, v.Source = number, kind
		v.Buyer.Name = "Northwind Partners"
		v.Payment.Reference = "SETTLEMENT-987"
		v.References = []invoice.InvoiceReference{{Number: "PRE-2025"}}
		v.Notes = []string{"Spring inventory"}
		if err = repository.Save(ctx, work, v); err != nil {
			t.Fatal(err)
		}
		return d.ID
	}
	first := seed("a", "INV-2026-001", "structured")
	second := seed("b", "INV-2026-002", "structured")
	third := seed("c", "AI-003", "ai")
	for _, query := range []string{"Acme", "suppliez", "Northwind", "printer paper", "EUR", "119.00", "2026-09-19", "SETTLEMENT-987", "PRE-2025", "inventory", `"Printer paper"`, "missing OR Northwind"} {
		page, err := repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 20, Text: query})
		if err != nil || len(page.Items) != 3 {
			t.Fatalf("invoice property %q: %+v %v", query, page, err)
		}
	}
	for _, query := range []string{"HiddenDocumentTitleOnly", "Structured invoice 1789833424525000", "HiddenOcrOnly", "taxCurrency", "unrelatedmarscolony", "%_", "Acme -Printer", `"paper Printer"`} {
		page, err := repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 20, Text: query})
		if err != nil || len(page.Items) != 0 {
			t.Fatalf("excluded content or syntax %q: %+v %v", query, page, err)
		}
	}
	page, err := repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1, Text: "INV-2026-001"})
	if err != nil || len(page.Items) != 1 || page.Items[0].DocumentID != first {
		t.Fatalf("exact invoice number must rank first: %+v %v", page, err)
	}
	page, err = repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1, Text: "INV-2026-00", Source: "structured"})
	if err != nil || len(page.Items) != 1 || page.Items[0].DocumentID != second || page.NextCursor == "" {
		t.Fatalf("partial number and source: %+v %v", page, err)
	}
	more, err := repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1, Text: " INV-2026-00 ", Source: "structured", Cursor: page.NextCursor})
	if err != nil || len(more.Items) != 1 || more.Items[0].DocumentID != first || more.NextCursor != "" {
		t.Fatalf("stable search pagination: %+v %v", more, err)
	}
	for _, query := range []invoice.InvoiceQuery{
		{Limit: 1, Text: "Acme", Source: "structured", Cursor: page.NextCursor},
		{Limit: 1, Text: "INV-2026-00", Source: "ai", Cursor: page.NextCursor},
		{Limit: 1, Source: "structured", Cursor: page.NextCursor},
	} {
		if _, err = repository.List(ctx, f.actor, query); !errors.Is(err, invoice.ErrInvalid) {
			t.Fatalf("accepted changed criteria: %+v %v", query, err)
		}
	}
	page, err = repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 20, Text: "Acme", Source: "ai"})
	if err != nil || len(page.Items) != 1 || page.Items[0].DocumentID != third {
		t.Fatalf("combined AI source: %+v %v", page, err)
	}
	other := f.addActor(t)
	page, err = repository.List(ctx, other, invoice.InvoiceQuery{Limit: 20, Text: "Acme"})
	if err != nil || len(page.Items) != 0 {
		t.Fatalf("cross-library search: %+v %v", page, err)
	}
	page, err = repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1})
	if err != nil || page.NextCursor == "" {
		t.Fatal("browse cursor missing", err)
	}
	if _, err = repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1, Text: "  ", Cursor: page.NextCursor}); err != nil {
		t.Fatal("blank query must preserve browse cursor", err)
	}
	var vector string
	if err = f.connection.QueryRow(ctx, "SELECT search_vector::text FROM invoices WHERE document_id=$1", first).Scan(&vector); err != nil || !strings.Contains(vector, "printer") {
		t.Fatal("invoice search vector unavailable", vector, err)
	}
	page, err = repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 20, Text: "INV-2026-001"})
	if err != nil || len(page.Items) == 0 {
		t.Fatal("missing invoice for replacement", err)
	}
	replacement := page.Items[0]
	replacement.Notes = []string{"Updateduniquenote"}
	f.exec(t, `UPDATE document_processing SET generation=2,invoice_completed_generation=NULL,stage='invoicing',invoice_next_stage='embedding' WHERE document_id=$1`, first)
	work, err := repository.Work(ctx, document.DocumentJob{AccountID: f.actor.AccountID, DocumentID: first, Generation: 2})
	if err != nil {
		t.Fatal(err)
	}
	database := source.NewInvoiceDataSource(f.source.Database())
	broken, err := database.Get(ctx, f.actor, replacement.ID)
	if err != nil {
		t.Fatal(err)
	}
	broken.Number, broken.Notes = "BROKEN-REPLACEMENT", []string{"Neverpublishednote"}
	broken.Lines[0].UnitPrice = "not a decimal"
	if err = database.Save(ctx, work, &broken); err == nil {
		t.Fatal("invalid child write did not fail")
	}
	retained, err := repository.Get(ctx, f.actor, replacement.ID)
	if err != nil || retained.Number != replacement.Number || retained.Notes[0] != "Spring inventory" || retained.Lines[0].UnitPrice != "10.0000" {
		t.Fatalf("partial replacement escaped rollback: %+v %v", retained, err)
	}
	checkpoint, err := repository.Work(ctx, work.Job)
	if err != nil || checkpoint.Done {
		t.Fatal("failed relational write advanced checkpoint", err)
	}
	page, err = repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 20, Text: "Neverpublishednote"})
	if err != nil || len(page.Items) != 0 {
		t.Fatalf("failed relational write published search projection: %+v %v", page, err)
	}
	if err = repository.Save(ctx, work, &replacement); err != nil {
		t.Fatal(err)
	}
	page, err = repository.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 20, Text: "Updateduniquenote"})
	if err != nil || len(page.Items) != 1 || page.Items[0].DocumentID != first {
		t.Fatalf("changed invoice properties were not indexed: %+v %v", page, err)
	}
	if len(page.Items[0].Notes) != 1 || len(page.Items[0].Lines) != 1 {
		t.Fatal("replacement duplicated or retained old child rows", page.Items[0])
	}
}
