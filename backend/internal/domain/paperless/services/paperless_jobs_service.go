package services

import (
	"context"
	"errors"
	"time"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/paperless/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type PaperlessJobsService struct {
	repository p.PaperlessJobsRepository
	importer   *PaperlessImportService
	authority  p.PaperlessAuthority
}

func NewPaperlessJobsService(repository p.PaperlessJobsRepository, importer *PaperlessImportService, authority p.PaperlessAuthority) *PaperlessJobsService {
	return &PaperlessJobsService{repository: repository, importer: importer, authority: authority}
}
func (s *PaperlessJobsService) Settings(ctx context.Context, actor d.DocumentActor) (m.PaperlessSettings, error) {
	if err := s.authorize(ctx, actor, true); err != nil {
		return m.PaperlessSettings{}, err
	}
	return s.repository.Settings(ctx, actor)
}
func (s *PaperlessJobsService) UpdateSettings(ctx context.Context, actor d.DocumentActor, update m.PaperlessSettingsUpdate) (m.PaperlessSettings, error) {
	if err := s.authorize(ctx, actor, true); err != nil {
		return m.PaperlessSettings{}, err
	}
	if err := update.Validate(); err != nil {
		return m.PaperlessSettings{}, err
	}
	return s.repository.UpdateSettings(ctx, actor, update)
}
func (s *PaperlessJobsService) Create(ctx context.Context, a d.DocumentActor, id string, c m.PaperlessConnection) (m.PaperlessRun, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.PaperlessRun{}, err
	}
	if err := m.ValidatePaperlessStart(id, c); err != nil {
		return m.PaperlessRun{}, err
	}
	c.MaximumUnclosedRuns = m.PaperlessMaximumUnclosedRuns
	return s.repository.Create(ctx, a, id, c)
}
func (s *PaperlessJobsService) List(ctx context.Context, a d.DocumentActor, page m.PaperlessPageRequest) (m.PaperlessRunPage, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.PaperlessRunPage{}, err
	}
	if err := m.ValidatePaperlessRunPage(page); err != nil {
		return m.PaperlessRunPage{}, err
	}
	page.Projection = m.DefaultPaperlessStatusProjection()
	return s.repository.List(ctx, a, page)
}
func (s *PaperlessJobsService) Outcomes(ctx context.Context, a d.DocumentActor, id string, page m.PaperlessPageRequest) (m.PaperlessOutcomePage, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.PaperlessOutcomePage{}, err
	}
	return s.repository.Outcomes(ctx, a, id, page)
}
func (s *PaperlessJobsService) Get(ctx context.Context, a d.DocumentActor, id string) (m.PaperlessRun, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.PaperlessRun{}, err
	}
	return s.repository.Get(ctx, a, id)
}
func (s *PaperlessJobsService) Cancel(ctx context.Context, a d.DocumentActor, id string) (m.PaperlessRun, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.PaperlessRun{}, err
	}
	if _, err := s.repository.Get(ctx, a, id); err != nil {
		return m.PaperlessRun{}, err
	}
	for range 3 {
		facts, err := s.repository.RunFacts(ctx, id)
		if err != nil {
			return m.PaperlessRun{}, err
		}
		result, err := s.repository.Cancel(ctx, a, id, m.PlanPaperlessCancellation(facts))
		if !errors.Is(err, d.ErrConflict) {
			return result, err
		}
	}
	return m.PaperlessRun{}, d.ErrConflict
}
func (s *PaperlessJobsService) Next(ctx context.Context) (*m.PaperlessExecution, error) {
	return s.repository.Next(ctx)
}
func (s *PaperlessJobsService) Fail(ctx context.Context, id, code string) error {
	return s.Finish(ctx, id, "failed", code)
}
func (s *PaperlessJobsService) Closed(ctx context.Context, id string) error {
	return s.repository.Closed(ctx, id)
}
func (s *PaperlessJobsService) Step(ctx context.Context, id string) (bool, error) {
	w, err := s.Work(ctx, id)
	if err != nil {
		if code, terminal := failureCode(err); terminal {
			return true, s.Finish(ctx, id, "failed", code)
		}
		return false, err
	}
	if w.Run.CancelRequested {
		return true, s.Finish(ctx, id, "cancelled", "")
	}
	if w.Run.State != "queued" && w.Run.State != "running" {
		return true, nil
	}
	if w.Run.Stage == "discovering" {
		page, err := s.importer.Preview(ctx, w.Connection, w.Page)
		if err == nil {
			err = s.authorizeRun(ctx, id)
		}
		if err == nil {
			err = s.recordPage(ctx, id, w.Page, page)
		}
		if err != nil {
			if code, terminal := failureCode(err); terminal {
				return true, s.Finish(ctx, id, "failed", code)
			}
			return false, err
		}
		return false, nil
	}
	if len(w.Items) == 0 {
		if w.Waiting {
			return false, nil
		}
		return true, s.Finish(ctx, id, "succeeded", "")
	}
	return s.retrieveBatch(ctx, id, w)
}

func (s *PaperlessJobsService) recordPage(ctx context.Context, id string, page int, input m.PaperlessPage) error {
	facts, err := s.repository.PageFacts(ctx, id)
	if err != nil {
		return err
	}
	command, err := m.PlanPaperlessPage(facts, page, input)
	if err != nil || command == nil {
		return err
	}
	return s.repository.RecordPage(ctx, id, *command)
}

func (s *PaperlessJobsService) RecordPage(ctx context.Context, id string, page int, input m.PaperlessPage) error {
	if err := s.authorizeRun(ctx, id); err != nil {
		return err
	}
	return s.recordPage(ctx, id, page, input)
}

func (s *PaperlessJobsService) Work(ctx context.Context, id string) (m.PaperlessWork, error) {
	if err := s.authorizeRun(ctx, id); err != nil {
		return m.PaperlessWork{}, err
	}
	for range 3 {
		facts, err := s.repository.RunFacts(ctx, id)
		if err != nil {
			return m.PaperlessWork{}, err
		}
		work, err := s.repository.Work(ctx, id, m.PlanPaperlessWork(facts))
		if !errors.Is(err, d.ErrConflict) {
			return work, err
		}
	}
	return m.PaperlessWork{}, d.ErrConflict
}

func (s *PaperlessJobsService) retrieveBatch(ctx context.Context, id string, work m.PaperlessWork) (bool, error) {
	child, cancel := context.WithCancel(ctx)
	defer cancel()
	results := make(chan error, len(work.Items))
	for _, item := range work.Items {
		go func() {
			operation, done := context.WithDeadline(child, item.Deadline)
			defer done()
			results <- s.retrieveItem(operation, id, work, item)
		}()
	}
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	var firstError error
	var terminalCode string
	cancelled := false
	remaining := len(work.Items)
	for remaining > 0 {
		select {
		case err := <-results:
			remaining--
			if err != nil && firstError == nil {
				firstError = err
				if code, terminal := failureCode(err); terminal {
					terminalCode = code
				}
				cancel()
			}
		case <-ticker.C:
			active, err := s.repository.RunActive(child, id)
			if err != nil && firstError == nil {
				firstError = err
				cancel()
			}
			if err == nil && !active {
				cancelled = true
				cancel()
			}
		}
	}
	cleanup, stop := context.WithTimeout(context.Background(), 5*time.Second)
	defer stop()
	if err := s.repository.ReleaseClaims(cleanup, id, work.Items); err != nil && firstError == nil {
		firstError = err
	}
	if ctx.Err() != nil {
		return false, ctx.Err()
	}
	if cancelled {
		return true, s.Finish(ctx, id, "cancelled", "")
	}
	if terminalCode != "" {
		return true, s.Finish(ctx, id, "failed", terminalCode)
	}
	return false, firstError
}

func (s *PaperlessJobsService) retrieveItem(ctx context.Context, id string, work m.PaperlessWork, item m.PaperlessRetrieval) error {
	if err := s.authorizeRun(ctx, id); err != nil {
		return err
	}
	actor := work.Actor
	actor.ImportSourceID, actor.ImportClaimToken = item.Document.ID, item.ClaimToken
	result, err := s.importer.Import(ctx, actor, work.Connection, item.Document.ID)
	outcome := m.PaperlessOutcome{SourceID: item.Document.ID, Title: item.Document.Title, ClaimToken: item.ClaimToken, Status: "imported", DocumentID: result.DocumentID}
	if result.Duplicate {
		outcome.Status = "duplicate"
	}
	if err != nil {
		code, terminal := failureCode(err)
		if !terminal {
			return err
		}
		switch code {
		case "source_not_found", "invalid_metadata", "body_too_large", "unsupported_media_type":
			outcome.Status = "failed"
			outcome.FailureCode = code
		default:
			return err
		}
	}
	if err := s.authorizeRun(ctx, id); err != nil {
		return err
	}
	return s.repository.RecordOutcome(ctx, id, outcome)
}
func failureCode(err error) (string, bool) {
	var f m.PaperlessFailure
	if errors.As(err, &f) {
		return f.Code, f.Code != "source_unavailable" && f.Code != "source_busy"
	}
	if errors.Is(err, d.ErrUnauthorized) || errors.Is(err, d.ErrForbidden) || errors.Is(err, d.ErrPasswordChangeRequired) {
		return "permission_revoked", true
	}
	if errors.Is(err, d.ErrTooLarge) {
		return "body_too_large", true
	}
	if errors.Is(err, d.ErrUnsupportedMedia) {
		return "unsupported_media_type", true
	}
	var validation d.DocumentValidationError
	if errors.As(err, &validation) {
		return "invalid_metadata", true
	}
	return "unavailable", false
}

func (s *PaperlessJobsService) Finish(ctx context.Context, id, state, code string) error {
	for range 3 {
		facts, err := s.repository.RunFacts(ctx, id)
		if err != nil {
			return err
		}
		command, err := m.PlanPaperlessFinish(facts, state, code)
		if err != nil || !command.Apply {
			return err
		}
		err = s.repository.Finish(ctx, id, command)
		if !errors.Is(err, d.ErrConflict) {
			return err
		}
	}
	return d.ErrConflict
}
