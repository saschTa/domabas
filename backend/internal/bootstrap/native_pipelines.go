package bootstrap

import (
	"context"
	"errors"
	"fmt"
	"time"

	chatcontainer "github.com/domabas/domabas/backend/internal/bootstrap/chat"
	documentcontainer "github.com/domabas/domabas/backend/internal/bootstrap/document"
	emailcontainer "github.com/domabas/domabas/backend/internal/bootstrap/email"
	schedulercontainer "github.com/domabas/domabas/backend/internal/bootstrap/scheduler"
	"github.com/domabas/domabas/backend/internal/data/jobs"
	cm "github.com/domabas/domabas/backend/internal/domain/chat/models"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	e "github.com/domabas/domabas/backend/internal/domain/email/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/services"
	paperless "github.com/domabas/domabas/backend/internal/domain/paperless/services"
	"github.com/google/uuid"
)

type nativePipelines struct {
	executor    *jobs.NativeExecutor
	documents   *documentcontainer.DocumentContainer
	invoices    *invoice.InvoiceService
	email       *emailcontainer.EmailContainer
	chat        *chatcontainer.ChatContainer
	paperless   *paperless.PaperlessJobsService
	scheduler   *schedulercontainer.SchedulerContainer
	maintenance time.Time
}
type documentQueue interface {
	Claim(context.Context, int, time.Duration, ...string) ([]d.DocumentOutboxLease, error)
	Pending(context.Context, int) ([]d.DocumentPendingJob, error)
	Acknowledge(context.Context, d.DocumentOutboxLease, string, string) error
	ResolveExecution(context.Context, d.DocumentPendingJob, string, string, bool) error
	Fail(context.Context, d.DocumentJob, string) error
}

func (p *nativePipelines) poll(ctx context.Context) error {
	var maintenance error
	if time.Since(p.maintenance) >= time.Minute {
		maintenance = errors.Join(p.documents.Ingestion().ReapUploads(ctx), p.email.Polling().Cleanup(ctx), p.email.Rotation().Rotate(ctx), p.documents.Thumbnails().Discover(ctx))
		p.maintenance = time.Now()
	}
	return errors.Join(maintenance, p.documentJobs(ctx, p.documents.Ingestion(), "native-ingestion"), p.documentJobs(ctx, p.documents.AI(), "native-ai"), p.thumbnailJobs(ctx), p.emailJobs(ctx), p.paperlessJobs(ctx), p.chatJobs(ctx))
}
func (p *nativePipelines) documentJobs(ctx context.Context, q documentQueue, queue string) error {
	leases, err := q.Claim(ctx, 1, 30*time.Second, queue)
	if err != nil {
		return err
	}
	for _, lease := range leases {
		r, err := p.executor.Execution(ctx, lease.WorkflowID)
		if err != nil {
			return err
		}
		if err = q.Acknowledge(ctx, lease, lease.WorkflowID, r.RunID); err != nil {
			return err
		}
		p.startDocument(ctx, q, r, lease.Job, lease.SplitPipeline)
	}
	pending, err := q.Pending(ctx, 40)
	if err != nil {
		return err
	}
	for _, job := range pending {
		if job.RunID == "" {
			if err = q.ResolveExecution(ctx, job, "", "delivery_timeout", true); err != nil {
				return err
			}
			continue
		}
		r, err := p.executor.Execution(ctx, job.WorkflowID)
		if err != nil {
			return err
		}
		if r.RunID != job.RunID {
			return fmt.Errorf("retained document execution %s requires legacy drain", job.WorkflowID)
		}
		if r.Outcome != "" {
			code := r.Outcome
			if code == "done" {
				code = "processing_incomplete"
			}
			if err = q.ResolveExecution(ctx, job, r.RunID, code, false); err != nil {
				return err
			}
			continue
		}
		if job.State == "cancelled" || job.State == "superseded" || job.State == "failed" {
			if !p.executor.Cancel(r.ID) {
				if err = q.ResolveExecution(ctx, job, r.RunID, "processing_incomplete", false); err != nil {
					return err
				}
			}
			continue
		}
		p.startDocument(ctx, q, r, job.Job, job.SplitPipeline)
	}
	return nil
}

type documentStep struct {
	resource string
	call     func(context.Context, d.DocumentJob) error
}

func (p *nativePipelines) startDocument(ctx context.Context, q documentQueue, r jobs.NativeExecution, job d.DocumentJob, split bool) {
	ing := p.documents.Ingestion()
	ai := []documentStep{{"pipeline:invoice", p.invoices.ExtractInvoice}, {"pipeline:tags", p.documents.Properties().Enrich}}
	stages := []documentStep{{"stage:thumbnail", p.documents.IngestionThumbnail}, {"stage:ocr", ing.Extract}}
	runStage := func(ctx context.Context, stage documentStep) error {
		call := func(ctx context.Context) error {
			ctx = jobs.WithInferencePermit(ctx, func(ctx context.Context, endpoint string, call func(context.Context) error) error {
				return p.scheduler.Inference(ctx, r.ID, stage.resource, endpoint, call)
			})
			return stage.call(ctx, job)
		}
		if stage.resource == "" {
			return call(ctx)
		}
		return p.scheduler.RunStep(ctx, r.ID, stage.resource, call)
	}
	if job.AIAttempt > 0 {
		stages = []documentStep{{call: func(ctx context.Context, _ d.DocumentJob) error {
			type result struct {
				code string
				err  error
			}
			branch := func(stage documentStep) result {
				code, err := r.Branch(ctx, stage.resource, func(ctx context.Context, n int) (string, error) {
					err := runStage(ctx, stage)
					if err == nil {
						return "done", nil
					}
					if ctx.Err() != nil || errors.Is(err, d.ErrStaleJob) {
						return "", err
					}
					var failure d.DocumentProcessingError
					if errors.As(err, &failure) && (!failure.Retryable || n >= 5) {
						return failure.Code, nil
					}
					if n >= 5 {
						return "processing_failed", nil
					}
					return "", err
				})
				return result{code, err}
			}
			invoice := make(chan result, 1)
			go func() { invoice <- branch(ai[0]) }()
			tags := branch(ai[1])
			billing := <-invoice
			if err := errors.Join(billing.err, tags.err); err != nil {
				return err
			}
			for _, completed := range []result{billing, tags} {
				if completed.code != "done" {
					return d.DocumentProcessingError{Code: completed.code}
				}
			}
			return nil
		}}, {call: p.documents.AI().Complete}}
	} else {
		if !split {
			stages = append(stages, ai...)
		}
		stages = append(stages, documentStep{"stage:embedding", ing.Embed}, documentStep{call: ing.Finalize})
	}
	r.Start(ctx, func(ctx context.Context, r *jobs.NativeExecution) (string, error) {
		for i, stage := range stages {
			err := r.Step(ctx, i, func(ctx context.Context, _ int) error {
				return runStage(ctx, stage)
			})
			if err != nil {
				if errors.Is(err, d.ErrStaleJob) {
					return "processing_incomplete", nil
				}
				var f d.DocumentProcessingError
				retry := !errors.As(err, &f) || f.Retryable
				if ctx.Err() != nil || retry && r.Attempts < 5 {
					return "", err
				}
				code := f.Code
				if code == "" {
					code = "processing_failed"
				}
				return code, q.Fail(ctx, job, code)
			}
		}
		return "done", nil
	})
}
func (p *nativePipelines) thumbnailJobs(ctx context.Context) error {
	s := p.documents.Thumbnails()
	claims, err := s.Claim(ctx, "native-thumbnail")
	if err != nil {
		return err
	}
	pending, err := s.Pending(ctx)
	if err != nil {
		return err
	}
	for _, j := range append(claims, pending...) {
		if j.TaskQueue == "ingestion-preview" {
			continue
		}
		r, err := p.executor.Execution(ctx, j.WorkflowID)
		if err != nil {
			return err
		}
		if j.RunID == "" {
			if err = s.Acknowledge(ctx, j, r.RunID); err != nil {
				return err
			}
		}
		if r.Outcome != "" {
			if err = s.Resolve(ctx, j, r.RunID, true, false); err != nil {
				return err
			}
			continue
		}
		r.Start(ctx, func(ctx context.Context, r *jobs.NativeExecution) (string, error) {
			err := p.scheduler.RunStep(ctx, r.ID, "stage:thumbnail", func(ctx context.Context) error { return s.Render(ctx, j) })
			if err != nil {
				if ctx.Err() != nil {
					return "", err
				}
				err = s.Finish(ctx, j, d.DocumentThumbnailFailure(err))
			}
			return "done", err
		})
	}
	return nil
}
func (p *nativePipelines) emailJobs(ctx context.Context) error {
	s := p.email.Polling()
	if err := s.Schedule(ctx); err != nil {
		return err
	}
	pending, err := s.PendingExecutions(ctx)
	if err != nil {
		return err
	}
	next, err := s.ClaimDelivery(ctx, "native-email")
	if err != nil {
		return err
	}
	if next != nil {
		pending = append(pending, *next)
	}
	for _, j := range pending {
		r, err := p.executor.Execution(ctx, j.WorkflowID)
		if err != nil {
			return err
		}
		if j.WorkflowRunID == "" {
			if err = s.AcknowledgeDelivery(ctx, j, r.RunID); err != nil {
				return err
			}
			j.WorkflowRunID = r.RunID
		}
		if r.Outcome != "" {
			code := r.Outcome
			if code == "done" {
				code = ""
			}
			if err = s.ResolveExecution(ctx, j, r.RunID, code, false); err != nil {
				return err
			}
			continue
		}
		r.Start(ctx, func(ctx context.Context, r *jobs.NativeExecution) (string, error) {
			for i := r.Next; i < 4; i++ {
				var more bool
				err := r.Step(ctx, i, func(ctx context.Context, n int) error {
					op, cancel := context.WithTimeout(ctx, 120*time.Second)
					defer cancel()
					deadline, _ := op.Deadline()
					a := e.EmailAttempt{RunID: j.RunID, WorkflowID: j.WorkflowID, WorkflowRunID: r.RunID, TaskQueue: j.TaskQueue, ActivityID: fmt.Sprint(i + 1), Token: uuid.NewString(), PageIndex: i, Number: n, Deadline: deadline, ExecutionStartedAt: j.FirstAttemptAt}
					result, err := s.Page(op, a)
					more = result.HasMore
					return err
				})
				if err != nil {
					if ctx.Err() != nil || r.Attempts < 2 {
						return "", err
					}
					var failure e.EmailFailure
					if errors.As(err, &failure) {
						return failure.Code, nil
					}
					return "processing_incomplete", nil
				}
				if !more {
					break
				}
			}
			return "done", nil
		})
	}
	return nil
}
func (p *nativePipelines) paperlessJobs(ctx context.Context) error {
	s := p.paperless
	j, err := s.Next(ctx)
	if err != nil || j == nil {
		return err
	}
	r, err := p.executor.Execution(ctx, "domabas-paperless-"+j.ID)
	if err != nil {
		return err
	}
	if r.Outcome != "" {
		return s.Closed(ctx, j.ID)
	}
	r.Start(ctx, func(ctx context.Context, r *jobs.NativeExecution) (string, error) {
		for ctx.Err() == nil {
			var done bool
			err := r.Step(ctx, r.Next, func(ctx context.Context, _ int) error { var err error; done, err = s.Step(ctx, j.ID); return err })
			if err != nil {
				if r.Attempts < 3 {
					return "", err
				}
				return "failed", s.Fail(ctx, j.ID, "retry_exhausted")
			}
			if done {
				return "done", nil
			}
			select {
			case <-ctx.Done():
				return "", ctx.Err()
			case <-time.After(100 * time.Millisecond):
			}
		}
		return "", ctx.Err()
	})
	return nil
}
func (p *nativePipelines) chatJobs(ctx context.Context) error {
	s := p.chat.Execution()
	batch, err := s.Dispatch(ctx)
	if err != nil {
		return err
	}
	for _, j := range batch {
		r, err := p.executor.Execution(ctx, j.WorkflowID)
		if err != nil {
			return err
		}
		if j.CancelRequested {
			if p.executor.Cancel(r.ID) {
				if err = s.ReleaseDelivery(ctx, j); err != nil {
					return err
				}
				continue
			}
			if err = s.Closed(ctx, j, "chat_cancelled"); err != nil {
				return err
			}
			continue
		}
		if r.Outcome != "" {
			code := r.Outcome
			if code == "done" {
				code = "chat_failed"
			}
			if err = s.Closed(ctx, j, code); err != nil {
				return err
			}
			continue
		}
		if err = s.Acknowledge(ctx, j, r.RunID); err != nil {
			return err
		}
		r.Start(ctx, func(ctx context.Context, r *jobs.NativeExecution) (string, error) {
			ctx = jobs.WithInferencePermit(ctx, func(ctx context.Context, endpoint string, work func(context.Context) error) error {
				return p.scheduler.Inference(ctx, r.ID, "chat", endpoint, work)
			})
			for r.Next <= cm.ChatMaxToolCalls {
				var done bool
				err := r.Step(ctx, r.Next, func(ctx context.Context, _ int) error {
					var err error
					done, err = s.RunStep(ctx, j.TurnID, r.Next)
					return err
				})
				if err != nil {
					var failure cm.ChatProcessingError
					typed := errors.As(err, &failure)
					if ctx.Err() != nil || (!typed || failure.Retryable) && r.Attempts < 5 {
						return "", err
					}
					code := "chat_failed"
					if typed {
						code = failure.Code
					}
					return code, s.Fail(ctx, j.TurnID, code)
				}
				if done {
					return "done", nil
				}
			}
			return "tool_limit", s.Fail(ctx, j.TurnID, "tool_limit")
		})
	}
	return nil
}
