package models

import "testing"

func TestPaperlessCancellationAndClosurePolicy(t *testing.T) {
	queued := PlanPaperlessCancellation(PaperlessRunFacts{State: "queued", Stage: "queued"})
	if !queued.ClearCredential || !queued.CloseExecution || queued.State != "cancelled" {
		t.Fatal(queued)
	}
	started := PlanPaperlessCancellation(PaperlessRunFacts{State: "queued", Stage: "queued", Started: true})
	if started.CloseExecution {
		t.Fatal("a possibly started execution was closed")
	}
	running := PlanPaperlessCancellation(PaperlessRunFacts{State: "running", Stage: "importing", Started: true})
	if running.ClearCredential || running.CloseExecution || running.State != "running" || !running.Cancel {
		t.Fatal(running)
	}
	finished, err := PlanPaperlessFinish(PaperlessRunFacts{State: "running", Cancelled: true}, "succeeded", "")
	if err != nil || finished.State != "cancelled" || !finished.ClearCredential {
		t.Fatal(finished, err)
	}
}

func TestPaperlessDiscoveryRejectsChangedSourceAndPreservesCheckpoint(t *testing.T) {
	total := 3
	facts := PaperlessPageFacts{Page: 2, Count: 2, Previous: 8, Total: &total}
	for _, input := range []PaperlessPage{{Total: 4, Items: []PaperlessDocument{{ID: 9}}}, {Total: 3, Items: []PaperlessDocument{{ID: 8}}}, {Total: 3, HasMore: true, Items: []PaperlessDocument{{ID: 9}}}} {
		if _, err := PlanPaperlessPage(facts, 2, input); err == nil {
			t.Fatal("changed source accepted", input)
		}
	}
	command, err := PlanPaperlessPage(facts, 2, PaperlessPage{Total: 3, Items: []PaperlessDocument{{ID: 9}}})
	if err != nil || command == nil || command.Stage != "importing" || command.Expected.Count != 2 {
		t.Fatal(command, err)
	}
	facts.Cancelled = true
	if command, err := PlanPaperlessPage(facts, 2, PaperlessPage{}); err != nil || command != nil {
		t.Fatal(command, err)
	}
}
