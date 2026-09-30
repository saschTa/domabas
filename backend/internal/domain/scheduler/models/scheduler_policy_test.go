package models

import (
	"errors"
	"testing"
)

func TestSchedulerPlanRejectsUnknownCapacityAndPreservesNoop(t *testing.T) {
	settings := SchedulerSettings{Revision: 2, OllamaQueueSize: 16, Resources: []SchedulerResource{{ID: "worker", Limit: 12, MaximumLimit: 256}, {ID: "ollama", Limit: 8, MaximumLimit: 8}}}
	for _, update := range []SchedulerSettingsUpdate{{ExpectedRevision: 1, Resources: []SchedulerResourceUpdate{{ID: "worker", Limit: 12}}}, {ExpectedRevision: 2, Resources: []SchedulerResourceUpdate{{ID: "unknown", Limit: 1}}}, {ExpectedRevision: 2, Resources: []SchedulerResourceUpdate{{ID: "ollama", Limit: 9}}}} {
		if _, err := PlanSchedulerSettings(settings, update); err == nil {
			t.Fatal("invalid update accepted", update)
		}
	}
	plan, err := PlanSchedulerSettings(settings, SchedulerSettingsUpdate{ExpectedRevision: 2, Resources: []SchedulerResourceUpdate{{ID: "worker", Limit: 12}}})
	if err != nil || len(plan.Changes) != 0 || len(plan.ExpectedResources) != 2 {
		t.Fatal(plan, err)
	}
	if _, err := PlanSchedulerSettings(settings, SchedulerSettingsUpdate{ExpectedRevision: 1, Resources: []SchedulerResourceUpdate{{ID: "worker", Limit: 12}}}); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
}

func TestSchedulerAdmissionRequiresCompleteVectorAndNoOlderFeasibleWork(t *testing.T) {
	for _, test := range []struct {
		state                      string
		blocked, fits, older, want bool
	}{{"active", true, false, true, true}, {"released", false, true, false, false}, {"waiting", false, true, false, true}, {"waiting", true, true, false, false}, {"waiting", false, false, false, false}, {"waiting", false, true, true, false}} {
		if got := SchedulerCanAdmit(test.state, test.blocked, test.fits, test.older); got != test.want {
			t.Fatal(test, got)
		}
	}
	if SchedulerResourceMaximum("ollama", 17) != 8 || SchedulerResourceMaximum("ollama", 1024) != 256 || SchedulerResourceMaximum("worker", 16) != 256 {
		t.Fatal("resource limits changed")
	}
}
