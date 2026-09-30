package models

import (
	"errors"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	"testing"
)

func TestInvoiceWorkPlansRetainedAndIndependentStages(t *testing.T) {
	for _, stage := range []string{"enriching", "embedding", "finalizing"} {
		plan, err := PlanInvoiceWork(InvoiceWork{Stage: stage})
		if err != nil || plan.ResumeStage != stage {
			t.Fatal(stage, plan, err)
		}
	}
	plan, err := PlanInvoiceWork(InvoiceWork{Stage: "invoicing", ResumeStage: "embedding"})
	if err != nil || plan.ResumeStage != "embedding" {
		t.Fatal(plan, err)
	}
	plan, err = PlanInvoiceWork(InvoiceWork{Stage: "queued", Job: d.DocumentJob{AIAttempt: 1}})
	if err != nil || plan.ResumeStage != "enriching" {
		t.Fatal(plan, err)
	}
	if _, err := PlanInvoiceWork(InvoiceWork{Stage: "extracting"}); !errors.Is(err, d.ErrStaleJob) {
		t.Fatal(err)
	}
}

func TestInvoiceSaveDistinguishesNegativeSkippedAndStructured(t *testing.T) {
	for _, source := range []string{"ai", "structured", ""} {
		plan, _, err := PlanInvoiceSave(InvoiceWork{ClassifierVersion: 1, ExistingSource: source}, nil)
		if err != nil || plan.RemovePreviousAI {
			t.Fatal("new classification removed prior evidence", plan, err)
		}
	}
	for _, test := range []struct {
		source       string
		skip, remove bool
	}{{"ai", false, true}, {"structured", false, false}, {"ai", true, false}, {"", false, true}} {
		plan, _, err := PlanInvoiceSave(InvoiceWork{ExistingSource: test.source, Skipped: test.skip}, nil)
		if err != nil || plan.RemovePreviousAI != test.remove {
			t.Fatal(test, plan, err)
		}
	}
	value := &Invoice{Source: "ai", Number: "I-1", Currency: "EUR", Seller: InvoiceParty{Name: "Seller"}}
	plan, result, err := PlanInvoiceSave(InvoiceWork{ExistingSource: "structured"}, value)
	if err != nil || !plan.Skipped || result != nil || plan.RemovePreviousAI {
		t.Fatal(plan, result, err)
	}
}
