package models

import (
	"errors"
	"testing"
	"time"
)

func TestDocumentAcceptanceRequiresLiveStagedUpload(t *testing.T) {
	now := time.Unix(100, 0)
	facts := DocumentUploadAcceptanceFacts{State: "receiving", ExpiresAt: now.Add(time.Minute), Reference: DocumentFileReference{File: DocumentFile{SHA256: "hash"}}}
	command, err := PlanDocumentUploadAcceptance(facts, DocumentMetadata{Title: "accepted"}, now)
	if err != nil || command.ProcessingState != "queued" || command.ProcessingStage != "queued" || command.ReservationState != "accepted" || !command.CreatedAt.Equal(now) {
		t.Fatalf("accept: %+v %v", command, err)
	}
	for _, change := range []func(*DocumentUploadAcceptanceFacts){func(f *DocumentUploadAcceptanceFacts) { f.State = "accepted" }, func(f *DocumentUploadAcceptanceFacts) { f.ExpiresAt = now }, func(f *DocumentUploadAcceptanceFacts) { f.Reference.File.SHA256 = "" }} {
		invalid := facts
		change(&invalid)
		if _, err = PlanDocumentUploadAcceptance(invalid, DocumentMetadata{}, now); !errors.Is(err, ErrConflict) {
			t.Fatalf("invalid acceptance %+v: %v", invalid, err)
		}
	}
}

func TestDocumentImportDispositionKeepsRootAndAttachmentCountersSeparate(t *testing.T) {
	for _, test := range []struct {
		path, media string
		valid, root bool
	}{{"0", "message/rfc822", true, true}, {"1", "application/pdf", true, false}, {"0", "application/pdf", false, true}, {"1", "message/rfc822", false, false}} {
		facts := DocumentImportAcceptanceFacts{Path: test.path, Reference: DocumentFileReference{File: DocumentFile{SHA256: "hash", MediaType: test.media}}}
		command, err := PlanDocumentImportAcceptance(facts, DocumentMetadata{})
		if !test.valid {
			if !errors.Is(err, ErrUnsupportedMedia) {
				t.Fatalf("invalid %+v: %v", test, err)
			}
			continue
		}
		if err != nil || command.Created.State != "accepted" || command.Reused.State != "reused" || command.Created.Parent != test.root || command.Reused.Parent != test.root {
			t.Fatalf("disposition %+v: %+v %v", test, command, err)
		}
		if test.root {
			if command.Created.MessagesAccepted != 1 || command.Reused.MessagesReused != 1 || command.Created.AttachmentsAccepted != 0 || command.Reused.AttachmentsReused != 0 {
				t.Fatalf("root counters %+v", command)
			}
		} else if command.Created.AttachmentsAccepted != 1 || command.Reused.AttachmentsReused != 1 || command.Created.MessagesAccepted != 0 || command.Reused.MessagesReused != 0 {
			t.Fatalf("attachment counters %+v", command)
		}
	}
}

func TestDocumentAIEnqueueRetainsManualAndStructuredEvidence(t *testing.T) {
	for _, test := range []struct{ properties, invoice, evidence, manual, queued bool }{{false, false, false, false, false}, {true, false, false, false, true}, {false, true, false, false, true}, {false, false, true, true, true}} {
		invoice := test.invoice
		configuration := DocumentProcessingConfiguration{LLM: DocumentLLMConfiguration{Enabled: test.properties, InvoiceEnabled: &invoice}}
		command := PlanDocumentAIEnqueue(DocumentAIEnqueueFacts{HasInvoiceEvidence: test.evidence, ManualText: test.manual}, configuration)
		if (command.Status == "queued") != test.queued || command.Finished == test.queued || (command.TextSource == "manual") != test.manual {
			t.Fatalf("AI enqueue %+v: %+v", test, command)
		}
	}
}

func TestDocumentAIRetryReplayIsScopedAndRevisionBound(t *testing.T) {
	actor := DocumentActor{AccountID: "account", UserID: "user"}
	input := DocumentReindexRequest{RequestID: "11111111-1111-4111-8111-111111111111", ConfigurationRevision: 4}
	facts := DocumentAIRetryFacts{RequestExists: true, RequestAccount: actor.AccountID, RequestOwner: actor.UserID, RequestDocument: "document", RequestRevision: 4}
	if _, existing, err := PlanDocumentAIRetry(actor, "document", input, facts); err != nil || existing == nil {
		t.Fatalf("replay: %v", err)
	}
	facts.RequestOwner = "other"
	if _, _, err := PlanDocumentAIRetry(actor, "document", input, facts); !errors.Is(err, ErrNotFound) {
		t.Fatalf("foreign replay: %v", err)
	}
	facts.RequestOwner = actor.UserID
	facts.RequestRevision = 5
	if _, _, err := PlanDocumentAIRetry(actor, "document", input, facts); !errors.Is(err, ErrConflict) {
		t.Fatalf("changed request: %v", err)
	}
}

func TestDocumentAICompletionAllowsOnlyCurrentCompleteAttemptOrReplay(t *testing.T) {
	for _, test := range []struct {
		facts         DocumentAICompletionFacts
		replay, valid bool
	}{
		{DocumentAICompletionFacts{Status: "succeeded"}, true, true},
		{DocumentAICompletionFacts{Status: "running", Stage: "complete", Current: true}, false, true},
		{DocumentAICompletionFacts{Status: "running", Stage: "enriching", Current: true}, false, false},
		{DocumentAICompletionFacts{Status: "failed", Stage: "complete", Current: true}, false, false},
		{DocumentAICompletionFacts{Status: "running", Stage: "complete"}, false, false},
	} {
		replay, err := test.facts.CompletionReplay()
		if (err == nil) != test.valid || replay != test.replay {
			t.Fatalf("completion %+v: %v %v", test, replay, err)
		}
	}
}
