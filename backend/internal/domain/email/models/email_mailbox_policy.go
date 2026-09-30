package models

import "time"

type EmailMailboxFacts struct {
	Exists                         bool
	UIDValidity                    int64
	MaxAgeDays, ProviderMaxAgeDays int
	Cursor                         EmailCursor
}

type EmailPendingQuery struct {
	Limit                                       int
	Cutoff                                      time.Time
	ExcludedState, InspectionState, FailureCode string
}

func NewEmailPendingQuery(limit int, cutoff time.Time) (EmailPendingQuery, error) {
	query := EmailPendingQuery{Limit: limit, Cutoff: cutoff, ExcludedState: "skipped", InspectionState: "complete", FailureCode: "age_excluded"}
	if limit < 0 || limit > 100 {
		return query, EmailValidationError{Message: "invalid page size"}
	}
	return query, nil
}

type EmailDiscoveryCommand struct {
	Expected, Next           EmailCursor
	Backfill, ReviveExcluded bool
	Through                  int64
	UIDs                     []int64
	MaxAgeDays               int
}

func PlanEmailDiscovery(facts EmailMailboxFacts, backfill bool, through int64, uids []int64) (EmailDiscoveryCommand, error) {
	command := EmailDiscoveryCommand{Expected: facts.Cursor, Next: facts.Cursor, Backfill: backfill, ReviveExcluded: backfill, Through: through, UIDs: uids, MaxAgeDays: facts.ProviderMaxAgeDays}
	if len(uids) > 100 {
		return command, EmailValidationError{Message: "too many discovered messages"}
	}
	lower, upper := facts.Cursor.LiveNext, facts.Cursor.LiveUpper
	if backfill {
		lower, upper = facts.Cursor.BackfillNext, facts.Cursor.BackfillUpper
	}
	if lower < 1 || through < lower-1 || through > upper {
		return command, ErrStaleAttempt
	}
	for _, uid := range uids {
		if uid < lower || uid > through {
			return command, ErrStaleAttempt
		}
	}
	if backfill {
		command.Next.BackfillNext = through + 1
		if command.Next.BackfillNext > command.Next.BackfillUpper {
			command.Next.BackfillNext, command.Next.BackfillUpper = 0, 0
		}
		command.Next.BackfillTurn = false
	} else {
		command.Next.LiveNext = through + 1
		command.Next.BackfillTurn = true
	}
	return command, nil
}

type EmailMailboxCommand struct {
	Expected                                                         EmailMailboxFacts
	UIDValidity                                                      int64
	MaxAgeDays                                                       int
	Cursor                                                           EmailCursor
	ReviveExcluded                                                   bool
	NextRetryTurn                                                    bool
	ObsoleteMessageState, ObsoleteInspectionState, ObsoletePartState string
}

func PlanEmailMailbox(facts EmailMailboxFacts, mailbox EmailMailbox) (EmailMailboxCommand, error) {
	command := EmailMailboxCommand{Expected: facts, UIDValidity: mailbox.UIDValidity, MaxAgeDays: facts.ProviderMaxAgeDays, Cursor: facts.Cursor, NextRetryTurn: !facts.Cursor.RetryTurn, ObsoleteMessageState: "skipped", ObsoleteInspectionState: "failed", ObsoletePartState: "failed"}
	if mailbox.UIDValidity < 1 || mailbox.UIDValidity > 1<<32-1 || mailbox.UIDNext < 1 || mailbox.UIDNext > 1<<32-1 {
		return command, EmailFailure{Code: "invalid_mailbox_identity"}
	}
	if !facts.Exists {
		command.Cursor = EmailCursor{MailboxGeneration: 1, LiveNext: 1, LiveUpper: mailbox.UIDNext - 1}
		return command, nil
	}
	if facts.UIDValidity != mailbox.UIDValidity {
		command.Cursor = EmailCursor{MailboxGeneration: facts.Cursor.MailboxGeneration + 1, LiveNext: 1, LiveUpper: mailbox.UIDNext - 1, RetryTurn: facts.Cursor.RetryTurn}
	} else {
		if command.Cursor.LiveNext > command.Cursor.LiveUpper {
			command.Cursor.LiveUpper = mailbox.UIDNext - 1
		}
		if facts.ProviderMaxAgeDays > facts.MaxAgeDays && mailbox.UIDNext > 1 {
			command.Cursor.BackfillNext = 1
			command.Cursor.BackfillUpper = mailbox.UIDNext - 1
		}
	}
	command.ReviveExcluded = facts.ProviderMaxAgeDays > facts.MaxAgeDays
	return command, nil
}
