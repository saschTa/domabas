package services

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type EmailPollingService struct {
	repository p.EmailPollingRepository
	dispatch   p.EmailDispatchRepository
	gateway    p.EmailGateway
	importer   p.EmailDocumentImporter
	now        func() time.Time
	authority  p.EmailAuthority
}

func NewEmailPollingService(repository p.EmailPollingRepository, dispatch p.EmailDispatchRepository, gateway p.EmailGateway, importer p.EmailDocumentImporter, now func() time.Time, authority p.EmailAuthority) *EmailPollingService {
	return &EmailPollingService{repository: repository, dispatch: dispatch, gateway: gateway, importer: importer, now: now, authority: authority}
}
func (s *EmailPollingService) Page(ctx context.Context, attempt m.EmailAttempt) (m.EmailPageResult, error) {
	work, err := s.ClaimAttempt(ctx, attempt)
	if err != nil {
		return m.EmailPageResult{}, err
	}
	attempt = work.Attempt
	session, err := s.gateway.Connect(ctx, work.Connection)
	if err != nil {
		return m.EmailPageResult{}, err
	}
	defer session.Close()
	if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
		return m.EmailPageResult{}, err
	}
	cursor, err := s.SetupMailbox(ctx, attempt, session.Info())
	if err != nil {
		return m.EmailPageResult{}, err
	}
	work.Run.MailboxGeneration = cursor.MailboxGeneration
	cutoff := s.now().UTC().AddDate(0, 0, -work.Provider.MaxAgeDays)
	pendingLimit := work.Provider.PageSize / 2
	if work.Provider.PageSize == 1 && cursor.RetryTurn {
		pendingLimit = 1
	}
	pending, err := s.PendingItems(ctx, attempt, pendingLimit, cutoff)
	if err != nil {
		return m.EmailPageResult{}, err
	}
	remaining := work.Provider.PageSize - len(pending)
	items := append([]m.EmailItem{}, pending...)
	selected := map[string]bool{}
	for _, item := range items {
		selected[item.ID] = true
	}
	for windows := 0; windows < 20 && remaining > 0; windows++ {
		live := cursor.LiveNext <= cursor.LiveUpper
		backfill := cursor.BackfillNext > 0 && cursor.BackfillNext <= cursor.BackfillUpper
		if !live && !backfill {
			break
		}
		useBackfill := backfill && (!live || cursor.BackfillTurn)
		from, upper := cursor.LiveNext, cursor.LiveUpper
		if useBackfill {
			from, upper = cursor.BackfillNext, cursor.BackfillUpper
		}
		discovery, err := session.Discover(ctx, from, upper, cutoff)
		if err != nil {
			return m.EmailPageResult{}, err
		}
		if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
			return m.EmailPageResult{}, err
		}
		through, uids := discovery.Through, discovery.UIDs
		if through < from || through > upper || len(uids) > 1000 {
			return m.EmailPageResult{}, m.EmailFailure{Code: "protocol_failed"}
		}
		previous := from - 1
		for _, uid := range uids {
			if uid <= previous || uid > through {
				return m.EmailPageResult{}, m.EmailFailure{Code: "protocol_failed"}
			}
			previous = uid
		}
		if len(uids) > remaining {
			uids = uids[:remaining]
			through = uids[len(uids)-1]
		}
		discovered, err := s.DiscoverItems(ctx, attempt, useBackfill, through, uids)
		if err != nil {
			return m.EmailPageResult{}, err
		}
		for _, item := range discovered {
			if !selected[item.ID] {
				items = append(items, item)
				selected[item.ID] = true
				remaining--
			}
		}
		if useBackfill {
			cursor.BackfillNext = through + 1
			cursor.BackfillTurn = false
		} else {
			cursor.LiveNext = through + 1
			cursor.BackfillTurn = true
		}
	}
	if remaining > 0 {
		extra, err := s.PendingItems(ctx, attempt, work.Provider.PageSize, cutoff)
		if err != nil {
			return m.EmailPageResult{}, err
		}
		for _, item := range extra {
			if remaining == 0 {
				break
			}
			if !selected[item.ID] {
				selected[item.ID] = true
				items = append(items, item)
				remaining--
			}
		}
	}
	for _, item := range items {
		if err = ctx.Err(); err != nil {
			return m.EmailPageResult{}, err
		}
		if err = s.message(ctx, work, item, session, cutoff); err != nil {
			return m.EmailPageResult{}, err
		}
	}
	if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
		return m.EmailPageResult{}, err
	}
	more, err := s.repository.HasMore(ctx, attempt)
	if err != nil {
		return m.EmailPageResult{}, err
	}
	if !more || attempt.PageIndex == 3 {
		err = s.Finish(ctx, attempt, more, "")
	}
	return m.EmailPageResult{HasMore: more}, err
}

func (s *EmailPollingService) ClaimAttempt(ctx context.Context, attempt m.EmailAttempt) (m.EmailWork, error) {
	provider, err := s.repository.Consent(ctx, attempt.RunID)
	if err != nil {
		return m.EmailWork{}, err
	}
	principal, err := s.authority.ResolveBackgroundAuthority(ctx, provider.AccountID, provider.OwnerID, provider.ConsentRevision)
	if err = emailAuthorityError(principal, err, true); err != nil {
		if errors.Is(err, m.ErrForbidden) {
			if retireErr := s.repository.Retire(ctx, m.EmailRevokedRun(attempt.RunID)); retireErr != nil {
				return m.EmailWork{}, retireErr
			}
		}
		return m.EmailWork{}, err
	}
	if !provider.Enabled {
		return m.EmailWork{}, m.ErrStaleAttempt
	}
	if attempt.Token == "" || attempt.Number < 1 || attempt.PageIndex < 0 || attempt.PageIndex > 3 || attempt.ActivityID == "" || attempt.WorkflowRunID == "" {
		return m.EmailWork{}, m.ErrStaleAttempt
	}
	attempt.ConsentRevision = principal.CredentialRevision
	return s.repository.ClaimAttempt(ctx, attempt, m.EmailPageAdmission())
}

func (s *EmailPollingService) SetStage(ctx context.Context, attempt m.EmailAttempt, stage string) error {
	if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
		return err
	}
	if stage != "discovering" && stage != "fetching" && stage != "importing" {
		return m.EmailValidationError{Message: "invalid email stage"}
	}
	return s.repository.SetStage(ctx, attempt, stage)
}
func importAuthority(work m.EmailWork, item m.EmailItem, part m.EmailPart) d.DocumentImportAuthority {
	return d.DocumentImportAuthority{ProviderID: work.Provider.ID, OwnerID: work.Provider.OwnerID, AccountID: work.Provider.AccountID, RunID: work.Run.ID, MessageID: item.ID, PartID: part.ID, AttemptToken: work.Attempt.Token, WorkflowRunID: work.Attempt.WorkflowRunID, ActivityID: work.Attempt.ActivityID, ProviderRevision: work.Provider.Revision, SourceGeneration: work.Provider.SourceGeneration, MailboxGeneration: item.MailboxGeneration, PageIndex: work.Attempt.PageIndex, ActivityAttempt: work.Attempt.Number, AttemptDeadline: work.Attempt.Deadline}
}
func outcome(err error) (string, bool) {
	var failure m.EmailFailure
	if errors.As(err, &failure) {
		return failure.Code, failure.Retryable
	}
	switch {
	case errors.Is(err, d.ErrUnsupportedMedia):
		return "unsupported_media", false
	case errors.Is(err, d.ErrTooLarge):
		return "resource_limit", false
	case errors.Is(err, d.ErrNotFound):
		return "document_deleted", false
	}
	var processing d.DocumentProcessingError
	if errors.As(err, &processing) {
		return processing.Code, processing.Retryable
	}
	return "import_failed", true
}
func fenced(err error) bool {
	return errors.Is(err, m.ErrStaleAttempt) || errors.Is(err, m.ErrForbidden) || errors.Is(err, d.ErrStaleJob) || errors.Is(err, d.ErrForbidden) || errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)
}
func filename(value, path string) string {
	value = strings.TrimSpace(strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || r == '/' || r == '\\' {
			return '_'
		}
		return r
	}, value))
	runes := []rune(value)
	if len(runes) > 200 {
		value = string(runes[:200])
	}
	if value == "" {
		value = "Attachment " + path
	}
	return value
}
func (s *EmailPollingService) message(ctx context.Context, work m.EmailWork, item m.EmailItem, session p.EmailMailboxSession, cutoff time.Time) error {
	attempt := work.Attempt
	if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
		return err
	}
	raw, err := s.repository.Part(ctx, attempt, item, "0", "email.eml", "message/rfc822")
	if err != nil {
		return err
	}
	authority := importAuthority(work, item, raw)
	if item.ParentDocumentID == "" && raw.DocumentID == "" {
		if err = s.SetStage(ctx, attempt, "fetching"); err != nil {
			return err
		}
		reservation, err := s.importer.Reserve(ctx, authority)
		if err != nil {
			return err
		}
		var metadata d.DocumentMetadata
		fetched, fetchErr := session.Fetch(ctx, item.UID, func(message m.EmailMessage) error {
			var err error
			metadata, err = s.importer.Stage(ctx, authority, reservation, fmt.Sprintf("email-%d.eml", item.UID), message.Reader)
			return err
		})
		if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
			return err
		}
		if fetchErr != nil {
			if fenced(fetchErr) {
				return fetchErr
			}
			code, retry := outcome(fetchErr)
			state := "failed"
			if retry {
				state = "pending"
			}
			return s.MessageOutcome(ctx, attempt, item, state, code, nil)
		}
		if fetched.InternalDate.Before(cutoff) {
			return s.MessageOutcome(ctx, attempt, item, "skipped", "age_excluded", &fetched.InternalDate)
		}
		if err = s.MessageOutcome(ctx, attempt, item, "fetched", "", &fetched.InternalDate); err != nil {
			return err
		}
		if err = s.SetStage(ctx, attempt, "importing"); err != nil {
			return err
		}
		accepted, err := s.importer.Accept(ctx, authority, reservation, metadata)
		if err != nil {
			if fenced(err) {
				return err
			}
			code, retry := outcome(err)
			state := "failed"
			if retry {
				state = "pending"
			}
			return s.MessageOutcome(ctx, attempt, item, state, code, &fetched.InternalDate)
		}
		item.ParentDocumentID = accepted.DocumentID
	} else if item.ParentDocumentID == "" {
		item.ParentDocumentID = raw.DocumentID
	}
	if err = s.SetStage(ctx, attempt, "importing"); err != nil {
		return err
	}
	supported := 0
	transient, contentFailures := false, false
	inspection, inspectErr := s.importer.Inspect(ctx, authority, func(part d.DocumentEmailPart) error {
		if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
			return err
		}
		current, err := s.repository.Part(ctx, attempt, item, part.Path, filename(part.Filename, part.Path), part.MediaType)
		if err != nil {
			return err
		}
		if current.DocumentID != "" {
			supported++
			return nil
		}
		if current.State == "failed" || current.State == "skipped" || current.State == "deleted" {
			return nil
		}
		if part.Reader == nil {
			contentFailures = contentFailures || part.Status == "failed"
			state := part.Status
			if state != "failed" {
				state = "skipped"
			}
			return s.PartOutcome(ctx, attempt, item, current, state, part.FailureCode)
		}
		partAuthority := importAuthority(work, item, current)
		reservation, err := s.importer.Reserve(ctx, partAuthority)
		if err != nil {
			return err
		}
		metadata, err := s.importer.Stage(ctx, partAuthority, reservation, filename(part.Filename, part.Path), part.Reader)
		if err == nil {
			supported++
			if supported > 20 {
				err = d.ErrTooLarge
			}
		}
		if err == nil {
			_, err = s.importer.Accept(ctx, partAuthority, reservation, metadata)
		}
		if err == nil {
			return nil
		}
		if fenced(err) {
			return err
		}
		code, retry := outcome(err)
		state := "failed"
		if code == "unsupported_media" {
			state = "skipped"
		} else {
			contentFailures = true
		}
		if retry {
			state = "pending"
			transient = true
		}
		return s.PartOutcome(ctx, attempt, item, current, state, code)
	})
	if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
		return err
	}
	if inspectErr != nil && fenced(inspectErr) {
		return inspectErr
	}
	if errors.Is(inspectErr, d.ErrNotFound) {
		return s.MessageOutcome(ctx, attempt, item, "deleted", "document_deleted", nil)
	}
	if inspectErr != nil {
		if code, retry := outcome(inspectErr); retry {
			return s.MessageOutcome(ctx, attempt, item, "pending", code, nil)
		}
	}
	if err = s.InspectionOutcome(ctx, attempt, item, inspectErr == nil, contentFailures || inspection.ContentFailures || inspectErr != nil); err != nil {
		return err
	}
	if transient {
		return s.MessageOutcome(ctx, attempt, item, "pending", "attachment_import_failed", nil)
	}
	return nil
}
func (s *EmailPollingService) Fail(ctx context.Context, attempt m.EmailAttempt, code string) error {
	provider, err := s.repository.Consent(ctx, attempt.RunID)
	if err != nil {
		return err
	}
	principal, err := s.authority.ResolveBackgroundAuthority(ctx, provider.AccountID, provider.OwnerID, provider.ConsentRevision)
	if err = emailAuthorityError(principal, err, true); err != nil {
		if errors.Is(err, m.ErrForbidden) {
			return s.repository.Retire(ctx, m.EmailRevokedRun(attempt.RunID))
		}
		return err
	}
	attempt.ConsentRevision = principal.CredentialRevision
	return s.Finish(ctx, attempt, false, code)
}
func (s *EmailPollingService) Schedule(ctx context.Context) error {
	candidates, err := s.dispatch.ScheduleCandidates(ctx)
	if err != nil {
		return err
	}
	for _, candidate := range candidates {
		principal, err := s.authority.ResolveBackgroundAuthority(ctx, candidate.AccountID, candidate.OwnerID, candidate.ConsentRevision)
		if err = emailAuthorityError(principal, err, true); errors.Is(err, m.ErrForbidden) {
			continue
		} else if err != nil {
			return err
		}
		trigger := "scheduled"
		if candidate.HasMore {
			trigger = "continuation"
		}
		if err = s.dispatch.ScheduleProvider(ctx, candidate, trigger); err != nil && !errors.Is(err, m.ErrConflict) && !errors.Is(err, m.ErrNotFound) {
			return err
		}
	}
	return nil
}
func (s *EmailPollingService) ClaimDelivery(ctx context.Context, queue string) (*m.EmailExecution, error) {
	id, err := s.dispatch.NextDelivery(ctx)
	if err != nil || id == "" {
		return nil, err
	}
	if err = s.authorizeRun(ctx, id); err != nil {
		if errors.Is(err, m.ErrForbidden) || errors.Is(err, m.ErrStaleAttempt) || errors.Is(err, m.ErrNotFound) {
			return nil, s.dispatch.Retire(ctx, m.EmailRevokedRun(id))
		}
		return nil, err
	}
	execution, err := s.dispatch.ClaimDelivery(ctx, queue, id)
	if errors.Is(err, m.ErrStaleAttempt) || errors.Is(err, m.ErrNotFound) {
		return nil, s.dispatch.Retire(ctx, m.EmailRevokedRun(id))
	}
	return execution, err
}
func (s *EmailPollingService) AcknowledgeDelivery(ctx context.Context, e m.EmailExecution, run string) error {
	return s.dispatch.AcknowledgeDelivery(ctx, e, run)
}
func (s *EmailPollingService) PendingExecutions(ctx context.Context) ([]m.EmailExecution, error) {
	return s.dispatch.PendingExecutions(ctx)
}
func (s *EmailPollingService) ResolveExecution(ctx context.Context, e m.EmailExecution, run, code string, missing bool) error {
	for range 3 {
		facts, err := s.dispatch.ExecutionFacts(ctx, e)
		if err != nil {
			return err
		}
		command, err := m.PlanEmailExecutionClosure(facts, e, run, code, missing)
		if err != nil || !command.Apply {
			return err
		}
		err = s.dispatch.ResolveExecution(ctx, command)
		if !errors.Is(err, m.ErrConflict) {
			return err
		}
	}
	return m.ErrConflict
}
func (s *EmailPollingService) Cleanup(ctx context.Context) error { return s.dispatch.Cleanup(ctx) }

func (s *EmailPollingService) Finish(ctx context.Context, attempt m.EmailAttempt, more bool, code string) error {
	if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
		return err
	}
	for range 3 {
		facts, err := s.repository.FinishFacts(ctx, attempt)
		if err != nil {
			return err
		}
		err = s.repository.Finish(ctx, m.PlanEmailRunFinish(facts, more, code))
		if !errors.Is(err, m.ErrConflict) {
			return err
		}
	}
	return m.ErrConflict
}

func (s *EmailPollingService) SetupMailbox(ctx context.Context, attempt m.EmailAttempt, mailbox m.EmailMailbox) (m.EmailCursor, error) {
	if err := s.authorizeRun(ctx, attempt.RunID); err != nil {
		return m.EmailCursor{}, err
	}
	for range 3 {
		facts, err := s.repository.MailboxFacts(ctx, attempt)
		if err != nil {
			return m.EmailCursor{}, err
		}
		command, err := m.PlanEmailMailbox(facts, mailbox)
		if err != nil {
			return m.EmailCursor{}, err
		}
		cursor, err := s.repository.SetupMailbox(ctx, attempt, command)
		if !errors.Is(err, m.ErrConflict) {
			return cursor, err
		}
	}
	return m.EmailCursor{}, m.ErrConflict
}

func (s *EmailPollingService) PendingItems(ctx context.Context, a m.EmailAttempt, limit int, cutoff time.Time) ([]m.EmailItem, error) {
	if err := s.authorizeRun(ctx, a.RunID); err != nil {
		return nil, err
	}
	query, err := m.NewEmailPendingQuery(limit, cutoff)
	if err != nil {
		return nil, err
	}
	return s.repository.PendingItems(ctx, a, query)
}
func (s *EmailPollingService) DiscoverItems(ctx context.Context, a m.EmailAttempt, backfill bool, through int64, uids []int64) ([]m.EmailItem, error) {
	if err := s.authorizeRun(ctx, a.RunID); err != nil {
		return nil, err
	}
	facts, err := s.repository.MailboxFacts(ctx, a)
	if err != nil {
		return nil, err
	}
	command, err := m.PlanEmailDiscovery(facts, backfill, through, uids)
	if err != nil {
		return nil, err
	}
	return s.repository.DiscoverItems(ctx, a, command)
}
