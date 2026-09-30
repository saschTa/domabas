package models

import (
	"errors"
	"math"
	"reflect"
	"testing"
	"time"
)

func TestDocumentRetryPlanRequiresRetryableFacts(t *testing.T) {
	for _, test := range []struct {
		state      string
		machine    bool
		generation int64
		allowed    bool
	}{
		{"failed", true, 1, true}, {"ready", false, 7, true}, {"ready", true, 1, false}, {"queued", false, 1, false}, {"processing", false, 1, false}, {"failed", false, math.MaxInt64, false},
	} {
		plan, err := PlanDocumentRetry(DocumentRetryFacts{State: test.state, HasMachineText: test.machine, Generation: test.generation})
		if (err == nil) != test.allowed || (test.allowed && plan.Generation != test.generation+1) {
			t.Fatalf("retry %+v: %+v %v", test, plan, err)
		}
	}
}

func TestDocumentCorrectionPlanChoosesEmptyTextPublication(t *testing.T) {
	for _, test := range []struct{ location, text, state, stage string }{
		{"staged", "", "queued", "finalizing"}, {"final", "", "ready", "complete"}, {"final", "corrected", "queued", "embedding"},
	} {
		facts := DocumentCorrectionFacts{Revision: 4, Generation: 8, Location: test.location}
		plan, err := PlanDocumentCorrection(facts, DocumentOCRCorrection{Revision: 4, Text: test.text})
		if err != nil || plan.State != test.state || plan.Stage != test.stage {
			t.Fatalf("correction %+v: %+v %v", test, plan, err)
		}
		if _, err = PlanDocumentCorrection(facts, DocumentOCRCorrection{Revision: 3, Text: test.text}); !errors.Is(err, ErrConflict) {
			t.Fatalf("stale OCR revision: %v", err)
		}
	}
}

func TestDocumentExtractedMetadataOnlyFillsEmptyFields(t *testing.T) {
	current := DocumentMetadata{Title: "Original", Description: "User description", Tags: []string{"user"}, Recipients: []string{}, CC: []string{"private"}, Sender: "", Subject: ""}
	extracted := DocumentMetadata{Title: "Model title", Description: "Model description", Tags: []string{"model"}, Sender: "sender", Subject: "subject"}
	merged := current.FillExtractedProperties(extracted)
	if merged.Title != current.Title || merged.Description != current.Description || !reflect.DeepEqual(merged.Tags, current.Tags) || !reflect.DeepEqual(merged.CC, current.CC) || merged.Sender != "sender" || merged.Subject != "subject" || merged.Recipients == nil {
		t.Fatalf("unexpected merge: %+v", merged)
	}
}

func TestDocumentCleanupBackoffAndRecurringSweep(t *testing.T) {
	now := time.Unix(100, 0)
	for _, test := range []struct{ attempts, seconds, next int }{{0, 5, 1}, {1, 10, 2}, {5, 160, 6}, {6, 300, 7}, {8, 300, 8}} {
		plan := PlanDocumentCleanup(DocumentCleanupLease{Attempts: test.attempts}, false, now)
		if plan.Attempts != test.next || !plan.NextAttempt.Equal(now.Add(time.Duration(test.seconds)*time.Second)) {
			t.Fatalf("backoff %+v: %+v", test, plan)
		}
	}
	plan := PlanDocumentCleanup(DocumentCleanupLease{Attempts: 8}, true, now)
	if plan.Attempts != 0 || !plan.NextAttempt.Equal(now.Add(5*time.Minute)) {
		t.Fatalf("success sweep: %+v", plan)
	}
}

func TestDocumentSearchPriorityBandsRemainDisjoint(t *testing.T) {
	if DocumentMetadataScorePriority+DocumentFuzzyScoreMinimum <= DocumentContentScorePriority+2 || DocumentContentScorePriority+DocumentFuzzyScoreMinimum <= DocumentSemanticScoreMaximum || DocumentFuzzyScoreMinimum != 0.3 || DocumentSemanticScoreMinimum != 0.55 {
		t.Fatal("search priority or acceptance policy changed")
	}
}

func TestDocumentExecutionRecoveryRetainsUnknownOwnership(t *testing.T) {
	for _, test := range []struct {
		code                 string
		missing, safe, close bool
	}{{"processing_incomplete", true, false, false}, {"processing_incomplete", true, true, true}, {"processing_incomplete", false, false, true}, {"", false, true, false}} {
		plan, err := PlanDocumentExecutionRecovery("run", "run", test.code, test.missing, test.safe)
		if err != nil || plan.Close != test.close {
			t.Fatalf("recovery %+v: %+v %v", test, plan, err)
		}
	}
	if _, err := PlanDocumentExecutionRecovery("old", "different", "processing_incomplete", false, true); !errors.Is(err, ErrStaleJob) {
		t.Fatalf("wrong retained execution: %v", err)
	}
}
