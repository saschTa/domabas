package models

import (
	"errors"
	"testing"
	"time"
)

func TestProviderEditDoesNotRenewConsentImplicitly(t *testing.T) {
	facts := EmailProviderUpdateFacts{Provider: EmailProvider{EmailSettings: EmailSettings{Enabled: true, Host: "old", Port: 993, Mailbox: "INBOX"}, Revision: 4, ConsentRevision: 2}, Credentials: EmailCredentials{Username: "user", Password: "secret"}, CredentialsAvailable: true, VaultAvailable: true}
	revision := int64(4)
	input := EmailProviderInput{EmailSettings: facts.Provider.EmailSettings, ExpectedRevision: &revision}
	input.Host = "new"
	command, err := PlanEmailProviderUpdate(facts, input, 3)
	if err != nil || !command.SourceChanged || command.RenewConsent || command.Noop || command.SupersededState != "superseded" {
		t.Fatalf("host change: %+v %v", command, err)
	}
	input.RenewConsent = true
	command, err = PlanEmailProviderUpdate(facts, input, 3)
	if err != nil || !command.RenewConsent {
		t.Fatalf("explicit renewal: %+v %v", command, err)
	}
	input = EmailProviderInput{EmailSettings: facts.Provider.EmailSettings}
	command, err = PlanEmailProviderUpdate(facts, input, 3)
	if err != nil || !command.Noop || command.RenewConsent {
		t.Fatalf("stale consent no-op: %+v %v", command, err)
	}
	if _, err = PlanEmailStart(facts, EmailStartRun{ExpectedRevision: 4}, 3); !errors.Is(err, ErrConflict) {
		t.Fatalf("stale consent start: %v", err)
	}
}

func TestEmailFinishClassifiesCountersAndBoundsRetry(t *testing.T) {
	facts := EmailRunFinishFacts{Work: EmailWork{Provider: EmailProvider{EmailSettings: EmailSettings{IntervalMinutes: 30}}, Run: EmailRun{Stage: "fetching", MessagesFailed: 1}}}
	if got := PlanEmailRunFinish(facts, false, ""); got.Status != "failed" || got.Delay != 30*time.Minute {
		t.Fatalf("entirely failed run: %+v", got)
	}
	facts.Work.Run.MessagesAccepted = 1
	if got := PlanEmailRunFinish(facts, true, ""); got.Status != "partial" || got.Delay != time.Second {
		t.Fatalf("partial continuation: %+v", got)
	}
	facts.RetryCount = 500
	if got := PlanEmailRunFinish(facts, false, "connection_failed"); got.Status != "failed" || got.Stage != "fetching" || got.Delay != 30*time.Minute || got.RetryCount != 501 {
		t.Fatalf("bounded provider retry: %+v", got)
	}
}

func TestMailboxResetAndWiderAgeKeepSeparateGenerations(t *testing.T) {
	facts := EmailMailboxFacts{Exists: true, UIDValidity: 10, MaxAgeDays: 5, ProviderMaxAgeDays: 10, Cursor: EmailCursor{MailboxGeneration: 3, LiveNext: 8, LiveUpper: 7, RetryTurn: true}}
	command, err := PlanEmailMailbox(facts, EmailMailbox{UIDValidity: 10, UIDNext: 20})
	if err != nil || command.Cursor.MailboxGeneration != 3 || command.Cursor.BackfillNext != 1 || command.Cursor.BackfillUpper != 19 || !command.ReviveExcluded || command.NextRetryTurn {
		t.Fatalf("wider age: %+v %v", command, err)
	}
	command, err = PlanEmailMailbox(facts, EmailMailbox{UIDValidity: 11, UIDNext: 6})
	if err != nil || command.Cursor.MailboxGeneration != 4 || command.Cursor.LiveNext != 1 || command.Cursor.LiveUpper != 5 || command.Cursor.BackfillNext != 0 || !command.Cursor.RetryTurn {
		t.Fatalf("UIDVALIDITY reset: %+v %v", command, err)
	}
	facts.Cursor = EmailCursor{LiveNext: 3, LiveUpper: 8}
	discovery, err := PlanEmailDiscovery(facts, false, 5, []int64{3, 5})
	if err != nil || discovery.Next.LiveNext != 6 || !discovery.Next.BackfillTurn {
		t.Fatalf("discovery advance: %+v %v", discovery, err)
	}
	if _, err = PlanEmailDiscovery(facts, false, 9, nil); !errors.Is(err, ErrStaleAttempt) {
		t.Fatalf("out-of-range discovery: %v", err)
	}
}

func TestEmailOutcomesPreserveAcceptedParentsAndCountOnce(t *testing.T) {
	facts := EmailMessageFacts{State: "accepted", ParentDocumentID: "document", RetryCount: 500}
	command, err := PlanEmailMessageOutcome(facts, "run", "pending", "download_failed", nil)
	if err != nil || command.State != "accepted" || command.Failed != 0 || command.RetryDelay != 24*time.Hour || command.InspectionState != "pending" {
		t.Fatalf("accepted retry: %+v %v", command, err)
	}
	facts = EmailMessageFacts{State: "pending", LastCountedRunID: "run"}
	command, err = PlanEmailMessageOutcome(facts, "run", "failed", "invalid_message", nil)
	if err != nil || command.Failed != 0 || command.InspectionState != "failed" {
		t.Fatalf("duplicate count: %+v %v", command, err)
	}
	part, err := PlanEmailPartOutcome(EmailPartFacts{Path: "0"}, "run", "failed", "invalid_message")
	if err != nil || part.Failed != 0 || !part.ContentFailure {
		t.Fatalf("root part accounting: %+v %v", part, err)
	}
	part, err = PlanEmailPartOutcome(EmailPartFacts{Path: "1"}, "run", "skipped", "unsupported_type")
	if err != nil || part.Skipped != 1 || part.ContentFailure {
		t.Fatalf("attachment skip: %+v %v", part, err)
	}
}

func TestMissingEmailExecutionWaitsForPermitGrace(t *testing.T) {
	permit := time.Unix(1000, 0)
	execution := EmailExecution{WorkflowID: "workflow", TaskQueue: "queue"}
	facts := EmailExecutionFacts{Status: "running", WorkflowID: execution.WorkflowID, TaskQueue: execution.TaskQueue, PermitEnd: &permit, ObservedAt: permit.Add(10 * time.Minute)}
	command, err := PlanEmailExecutionClosure(facts, execution, "", "", true)
	if err != nil || command.Apply {
		t.Fatalf("early missing history: %+v %v", command, err)
	}
	facts.ObservedAt = permit.Add(11 * time.Minute)
	command, err = PlanEmailExecutionClosure(facts, execution, "", "", true)
	if err != nil || !command.Apply || !command.FailRun || command.FailureCode != "processing_incomplete" {
		t.Fatalf("safe closure: %+v %v", command, err)
	}
	facts.WorkflowRunID = "owned-run"
	if _, err = PlanEmailExecutionClosure(facts, execution, "foreign-run", "", false); !errors.Is(err, ErrConflict) {
		t.Fatalf("foreign run closure: %v", err)
	}
}
