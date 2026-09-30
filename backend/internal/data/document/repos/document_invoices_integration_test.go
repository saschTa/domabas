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
	"reflect"
	"strings"
	"testing"
)

func TestInvoicesPersistExactMoneyFenceReplaysAndResolveCorrections(t *testing.T) {
	f := newIngestionFixture(t)
	repository := repos.NewInvoiceRepository(source.NewInvoiceDataSource(f.source.Database()))
	reader := invoiceservices.NewInvoiceService(repository, nil, nil, f.authority, nil)
	ctx := t.Context()
	prepare := func(hash, title string) invoice.InvoiceWork {
		d := f.accept(t, f.actor, strings.Repeat(hash, 64), title)
		j := document.DocumentJob{AccountID: f.actor.AccountID, DocumentID: d.ID, Generation: 1}
		f.admit(t, j)
		w, err := f.service.Work(ctx, j, "extracting")
		if err != nil {
			t.Fatal(err)
		}
		if err = f.service.SaveExtraction(ctx, j, w.Revision, "Invoice content", fixtures.CII); err != nil {
			t.Fatal(err)
		}
		work, err := reader.Work(ctx, j)
		if err != nil {
			t.Fatal(err)
		}
		if string(work.XML) != string(fixtures.CII) || work.Done {
			t.Fatal("missing embedded evidence")
		}
		return work
	}
	original := prepare("a", "Original invoice")
	v, err := source.ParseXML(ctx, fixtures.CII)
	if err != nil {
		t.Fatal(err)
	}
	v.TotalGross = "9007199254740993.190"
	v.PaidAmount, v.RoundingAmount = "10.000", "-0.001"
	v.Buyer = invoice.InvoiceParty{Name: "Buyer", TaxID: "BUYER-TAX", RegistrationID: "BUYER-REG", Address: "Buyer address", Country: "JP", Email: "buyer@example.test"}
	v.Seller.RegistrationID, v.Seller.Email = "SELLER-REG", "seller@example.test"
	v.Payment.BIC = "COBADEFFXXX"
	v.Lines = append(v.Lines, invoice.InvoiceLine{ID: "2", Description: "Unknown price", Quantity: "0.0001", UnitCode: "HUR"})
	v.Allowances = []invoice.InvoiceAllowance{{Charge: true, Reason: "Delivery", Amount: "1.190", TaxCategory: "S", TaxRate: "19.000"}, {Reason: "Discount", Amount: "-0.005"}}
	v.References = []invoice.InvoiceReference{{Number: "PRE-2025", IssueDate: "2025-12-01"}}
	v.Notes = append(v.Notes, "Second note")
	if err = reader.Save(ctx, original, v); err != nil {
		t.Fatal(err)
	}
	if err = reader.Save(ctx, original, v); err != nil {
		t.Fatal("idempotent save", err)
	}
	checkpoint, err := reader.Work(ctx, original.Job)
	if err != nil || !checkpoint.Done {
		t.Fatal("missing checkpoint", err)
	}
	page, err := reader.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1})
	if err != nil || len(page.Items) != 1 || page.Items[0].TotalGross != v.TotalGross {
		t.Fatalf("decimal round trip: %+v %v", page, err)
	}
	id := page.Items[0].ID
	expected := *v
	expected.ID, expected.DocumentID, expected.DocumentTitle, expected.CreatedAt = id, original.Job.DocumentID, page.Items[0].DocumentTitle, page.Items[0].CreatedAt
	if !reflect.DeepEqual(expected, page.Items[0]) {
		t.Fatalf("typed invoice round trip:\nwant %+v\ngot %+v", expected, page.Items[0])
	}
	var jsonColumns, lineCount, allowanceCount int
	if err = f.connection.QueryRow(ctx, `SELECT count(*) FROM information_schema.columns WHERE table_schema=current_schema() AND (table_name='invoices' OR table_name LIKE 'invoice\_%' ESCAPE '\') AND data_type IN ('json','jsonb')`).Scan(&jsonColumns); err != nil || jsonColumns != 0 {
		t.Fatalf("operational invoice JSON columns: %d %v", jsonColumns, err)
	}
	if err = f.connection.QueryRow(ctx, "SELECT count(*) FROM invoice_lines WHERE invoice_id=$1", id).Scan(&lineCount); err != nil || lineCount != 2 {
		t.Fatalf("typed ordered lines: %d %v", lineCount, err)
	}
	if err = f.connection.QueryRow(ctx, "SELECT count(*) FROM invoice_allowances WHERE invoice_id=$1", id).Scan(&allowanceCount); err != nil || allowanceCount != 2 {
		t.Fatalf("typed charges and allowances: %d %v", allowanceCount, err)
	}
	var amount, code string
	if err = f.connection.QueryRow(ctx, "SELECT total_gross::text,currency FROM invoices WHERE id=$1", id).Scan(&amount, &code); err != nil || amount != v.TotalGross || code != "EUR" {
		t.Fatalf("numeric storage %s %s %v", amount, code, err)
	}
	correction := prepare("b", "Correction")
	credit, err := source.ParseXML(ctx, fixtures.UBLCredit)
	if err != nil {
		t.Fatal(err)
	}
	correction.XML = fixtures.UBLCredit
	if err = reader.Save(ctx, correction, credit); err != nil {
		t.Fatal(err)
	}
	page, err = reader.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1})
	if err != nil || len(page.Items) != 1 || page.NextCursor == "" {
		t.Fatalf("pagination %+v %v", page, err)
	}
	detail, err := reader.Get(ctx, f.actor, page.Items[0].ID)
	if err != nil || len(detail.References) != 1 || detail.References[0].InvoiceID != id || detail.Currency != "KWD" || detail.TaxCurrency != "EUR" {
		t.Fatalf("correction %+v %v", detail, err)
	}
	second, err := reader.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1, Cursor: page.NextCursor})
	if err != nil || len(second.Items) != 1 || second.Items[0].ID != id || second.NextCursor != "" {
		t.Fatalf("second page %+v %v", second, err)
	}
	if _, err = reader.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1, Cursor: page.NextCursor, Source: "ai"}); !errors.Is(err, invoice.ErrInvalid) {
		t.Fatal("accepted wrong-filter cursor", err)
	}
	outsider := f.addActor(t)
	if _, err = reader.Get(ctx, outsider, id); !errors.Is(err, invoice.ErrNotFound) {
		t.Fatal("cross-library invoice", err)
	}
	if _, err = reader.List(ctx, outsider, invoice.InvoiceQuery{Limit: 1, Cursor: page.NextCursor}); !errors.Is(err, invoice.ErrInvalid) {
		t.Fatal("accepted cross-library cursor", err)
	}
	stale := prepare("c", "Obsolete invoice")
	f.exec(t, "UPDATE documents SET ocr_revision=ocr_revision+1 WHERE id=$1", stale.Job.DocumentID)
	if err = reader.Save(ctx, stale, v); !errors.Is(err, document.ErrStaleJob) {
		t.Fatal("stale OCR published", err)
	}
	f.exec(t, "UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2", f.actor.AccountID, f.actor.UserID)
	if _, err = reader.Get(ctx, f.actor, id); !errors.Is(err, invoice.ErrForbidden) {
		t.Fatal("revoked reader", err)
	}
	f.exec(t, "UPDATE memberships SET enabled=true WHERE account_id=$1 AND user_id=$2", f.actor.AccountID, f.actor.UserID)
	if err = f.service.Delete(ctx, f.actor, original.Job.DocumentID); err != nil {
		t.Fatal(err)
	}
	if _, err = reader.Get(ctx, f.actor, id); !errors.Is(err, invoice.ErrNotFound) {
		t.Fatal("source deletion retained invoice", err)
	}
	if err = f.connection.QueryRow(ctx, "SELECT count(*) FROM invoice_lines WHERE invoice_id=$1", id).Scan(&lineCount); err != nil || lineCount != 0 {
		t.Fatalf("source deletion retained lines: %d %v", lineCount, err)
	}
	detail, err = reader.Get(ctx, f.actor, detail.ID)
	if err != nil || detail.References[0].InvoiceID != "" || detail.References[0].Number != "INV-2026-001" {
		t.Fatalf("deleted reference lost text %+v %v", detail, err)
	}
}
