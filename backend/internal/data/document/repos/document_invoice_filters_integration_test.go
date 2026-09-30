//go:build integration

package repos_test

import (
	"errors"
	"fmt"
	"reflect"
	"strings"
	"testing"

	source "github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	repos "github.com/domabas/domabas/backend/internal/data/invoice/repos"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	services "github.com/domabas/domabas/backend/internal/domain/invoice/services"
	fixtures "github.com/domabas/domabas/backend/tests/fixtures/invoices"
)

func TestInvoiceFiltersSortAndVocabularyAcrossPages(t *testing.T) {
	f := newIngestionFixture(t)
	f.resourceCapacity(t, 64)
	service := services.NewInvoiceService(repos.NewInvoiceRepository(source.NewInvoiceDataSource(f.source.Database())), nil, nil, f.authority, nil)
	ctx := t.Context()
	for index := 0; index < 26; index++ {
		d := f.accept(t, f.actor, fmt.Sprintf("%064x", index+1), "Filter test")
		job := document.DocumentJob{AccountID: f.actor.AccountID, DocumentID: d.ID, Generation: 1}
		f.admit(t, job)
		work, err := f.service.Work(ctx, job, "extracting")
		if err != nil {
			t.Fatal(err)
		}
		if err = f.service.SaveExtraction(ctx, job, work.Revision, "Filter test", fixtures.CII); err != nil {
			t.Fatal(err)
		}
		iw, err := service.Work(ctx, job)
		if err != nil {
			t.Fatal(err)
		}
		v, err := source.ParseXML(ctx, fixtures.CII)
		if err != nil {
			t.Fatal(err)
		}
		v.Number = fmt.Sprintf("INV-%02d", index)
		v.Seller.Name = fmt.Sprintf("Supplier %02d", index)
		v.Buyer.Name = "Buyer"
		v.DueDate = "2026-10-01"
		v.IssueDate = "2026-09-01"
		v.TotalGross = "100.000000000001"
		if index >= 24 {
			v.DueDate = ""
			v.IssueDate = ""
		}
		if index == 0 {
			v.Seller.Name = strings.Repeat("😀", 4000)
			v.TotalGross = "100.000000000002"
		}
		if index == 1 {
			v.Seller.Name = "aCME %_"
			v.Currency = "USD"
		}
		if index == 2 {
			v.Seller.Name = "Acme"
			v.DueDate = "2026-11-01"
		}
		if err = service.Save(ctx, iw, v); err != nil {
			t.Fatal(err)
		}
		f.exec(t, `UPDATE invoices SET created_at='2026-09-01T00:00:00Z'::timestamptz + $2 * interval '1 day' WHERE document_id=$1`, d.ID, index)
	}
	collect := func(q invoice.InvoiceQuery) []string {
		t.Helper()
		q.Limit = 2
		seen := map[string]bool{}
		var result []string
		for pageNumber := 0; pageNumber < 20; pageNumber++ {
			page, err := service.List(ctx, f.actor, q)
			if err != nil {
				t.Fatalf("sort %s: %v", q.Sort, err)
			}
			for _, v := range page.Items {
				if seen[v.ID] {
					t.Fatal("duplicate page member", v.Number)
				}
				seen[v.ID] = true
				result = append(result, v.Number)
			}
			if page.NextCursor == "" {
				return result
			}
			q.Cursor = page.NextCursor
		}
		t.Fatal("unbounded pagination")
		return nil
	}
	ascending := make([]string, 26)
	for i := range ascending {
		ascending[i] = fmt.Sprintf("INV-%02d", i)
	}
	descending := make([]string, 26)
	for i := range descending {
		descending[i] = ascending[25-i]
	}
	for _, sort := range []string{"created_asc", "number_asc"} {
		if got := collect(invoice.InvoiceQuery{Sort: sort}); !reflect.DeepEqual(got, ascending) {
			t.Fatal(sort, got)
		}
	}
	for _, sort := range []string{"created_desc", "number_desc", "buyer_asc", "buyer_desc"} {
		if got := collect(invoice.InvoiceQuery{Sort: sort}); !reflect.DeepEqual(got, descending) {
			t.Fatal(sort, got)
		}
	}
	for _, sort := range []string{"due_asc", "due_desc", "issue_asc", "issue_desc"} {
		got := collect(invoice.InvoiceQuery{Sort: sort})
		if len(got) != 26 || got[24] != "INV-25" || got[25] != "INV-24" {
			t.Fatal("missing dates must remain reachable last", sort, got)
		}
		if sort == "due_desc" && got[0] != "INV-02" {
			t.Fatal("descending due date", got)
		}
		if sort == "due_asc" && got[23] != "INV-02" {
			t.Fatal("ascending due date", got)
		}
	}
	for _, sort := range []string{"seller_asc", "seller_desc"} {
		if got := collect(invoice.InvoiceQuery{Sort: sort, Text: "Buyer"}); len(got) != 26 {
			t.Fatal("search plus explicit text sort", sort, got)
		}
	}
	for _, q := range []invoice.InvoiceQuery{
		{Number: "INV-00"}, {Seller: strings.Repeat("😀", 4000)},
		{Currency: "EUR", TotalMin: "100.000000000002", TotalMax: "100.000000000002"},
		{CreatedFrom: "2026-09-01", CreatedTo: "2026-09-01"},
		{Sort: "number_asc", Buyer: "Buyer", Currency: "EUR", TypeCode: "380", Format: "cii", PaymentMeansCode: "58", IssueFrom: "2026-09-01", IssueTo: "2026-09-01", DueFrom: "2026-10-01", DueTo: "2026-10-01", TotalMin: "100.000000000002", Text: "Buyer"},
	} {
		if got := collect(q); !reflect.DeepEqual(got, []string{"INV-00"}) {
			t.Fatalf("combined filter %+v: %v", q, got)
		}
	}
	page, err := service.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 1, Sort: "due_asc", Currency: "EUR"})
	if err != nil || page.NextCursor == "" {
		t.Fatal(err)
	}
	for _, q := range []invoice.InvoiceQuery{{Limit: 1, Sort: "due_desc", Currency: "EUR"}, {Limit: 1, Sort: "due_asc", Currency: "USD"}, {Limit: 1, Sort: "due_asc", Currency: "EUR", DueFrom: "2026-01-01"}, {Limit: 1, Sort: "due_asc", Currency: "EUR", Text: "Buyer"}} {
		q.Cursor = page.NextCursor
		if _, err := service.List(ctx, f.actor, q); !errors.Is(err, invoice.ErrInvalid) {
			t.Fatal("reused changed-criteria cursor", err)
		}
	}
	values, err := service.FilterValues(ctx, f.actor, invoice.InvoiceFilterValueQuery{Limit: 20, Field: "seller"})
	if err != nil || len(values.Items) != 20 || values.NextCursor == "" {
		t.Fatal("first vocabulary page", values, err)
	}
	more, err := service.FilterValues(ctx, f.actor, invoice.InvoiceFilterValueQuery{Limit: 20, Field: "seller", Cursor: values.NextCursor})
	if err != nil || len(more.Items) != 6 || more.NextCursor != "" {
		t.Fatal("remaining vocabulary values", len(more.Items), err)
	}
	for _, q := range []invoice.InvoiceFilterValueQuery{{Limit: 20, Field: "buyer", Cursor: values.NextCursor}, {Limit: 20, Field: "seller", Text: "Acme", Cursor: values.NextCursor}} {
		if _, err := service.FilterValues(ctx, f.actor, q); !errors.Is(err, invoice.ErrInvalid) {
			t.Fatal("facet cursor not bound", err)
		}
	}
	for _, text := range []string{"ACME %_", "%_"} {
		got, err := service.FilterValues(ctx, f.actor, invoice.InvoiceFilterValueQuery{Limit: 20, Field: "seller", Text: text})
		if err != nil || !reflect.DeepEqual(got.Items, []string{"aCME %_"}) {
			t.Fatal("literal Unicode-aware value search", got, err)
		}
	}
	other := f.addActor(t)
	isolated, err := service.FilterValues(ctx, other, invoice.InvoiceFilterValueQuery{Limit: 20, Field: "seller"})
	if err != nil || len(isolated.Items) != 0 {
		t.Fatal("cross-library vocabulary", isolated, err)
	}
	if _, err := service.FilterValues(ctx, other, invoice.InvoiceFilterValueQuery{Limit: 20, Field: "seller", Cursor: values.NextCursor}); !errors.Is(err, invoice.ErrInvalid) {
		t.Fatal("cross-library cursor", err)
	}
}
