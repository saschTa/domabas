package services

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/paperless/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type paperlessBlockingSource struct {
	p.PaperlessRepository
	started chan int64
	finish  chan struct{}
	active  atomic.Int32
}

func (s *paperlessBlockingSource) Original(ctx context.Context, _ m.PaperlessConnection, id int64) (m.PaperlessOriginal, error) {
	s.active.Add(1)
	defer s.active.Add(-1)
	s.started <- id
	select {
	case <-ctx.Done():
		return m.PaperlessOriginal{}, ctx.Err()
	case <-s.finish:
		return m.PaperlessOriginal{}, m.PaperlessFailure{Code: "invalid_metadata"}
	}
}

type paperlessReservationFixture struct{ p.PaperlessDocumentImporter }

func (s *paperlessReservationFixture) ReserveUpload(context.Context, d.DocumentActor) (d.DocumentUploadReservation, error) {
	return d.DocumentUploadReservation{ID: "test"}, nil
}
func (s *paperlessReservationFixture) AbandonUpload(context.Context, d.DocumentActor, d.DocumentUploadReservation) error {
	return nil
}

type paperlessBatchJobs struct {
	mockJobs
	source              *paperlessBlockingSource
	released            atomic.Bool
	releasedWhileActive atomic.Bool
	outcomes            atomic.Int32
}

func (s *paperlessBatchJobs) RecordOutcome(context.Context, string, m.PaperlessOutcome) error {
	s.outcomes.Add(1)
	return nil
}
func (s *paperlessBatchJobs) ReleaseClaims(context.Context, string, []m.PaperlessRetrieval) error {
	s.releasedWhileActive.Store(s.source.active.Load() != 0)
	s.released.Store(true)
	return nil
}

func TestPaperlessSingleStepOverlapsDistinctRetrievalsAndDrainsCancellation(t *testing.T) {
	for _, cancelWork := range []bool{false, true} {
		t.Run(map[bool]string{false: "complete", true: "cancel"}[cancelWork], func(t *testing.T) {
			source := &paperlessBlockingSource{started: make(chan int64, 3), finish: make(chan struct{})}
			jobs := &paperlessBatchJobs{source: source}
			jobs.work = m.PaperlessWork{Run: m.PaperlessRun{State: "running", Stage: "importing"}, Actor: d.DocumentActor{ImportRunID: "run"}, Waiting: true}
			for id := int64(1); id <= 3; id++ {
				jobs.work.Items = append(jobs.work.Items, m.PaperlessRetrieval{Document: m.PaperlessDocument{ID: id}, ClaimToken: "claim", Deadline: time.Now().Add(time.Minute)})
			}
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			finished := make(chan error, 1)
			go func() {
				_, err := NewPaperlessJobsService(jobs, NewPaperlessImportService(source, &paperlessReservationFixture{}), paperlessTestAuthority{}).Step(ctx, "run")
				finished <- err
			}()
			seen := map[int64]bool{}
			for range 3 {
				select {
				case id := <-source.started:
					if seen[id] {
						t.Fatal("duplicate retrieval")
					}
					seen[id] = true
				case <-time.After(2 * time.Second):
					t.Fatal("one import did not overlap three retrievals")
				}
			}
			if source.active.Load() != 3 {
				t.Fatal("retrievals did not remain concurrent")
			}
			if cancelWork {
				cancel()
			} else {
				close(source.finish)
			}
			select {
			case err := <-finished:
				if cancelWork != (err != nil) {
					t.Fatalf("cancellation=%v error=%v", cancelWork, err)
				}
			case <-time.After(2 * time.Second):
				t.Fatal("batch failed to drain")
			}
			if source.active.Load() != 0 || !jobs.released.Load() || jobs.releasedWhileActive.Load() {
				t.Fatal("capacity released before retrieval drain")
			}
			if !cancelWork && jobs.outcomes.Load() != 3 {
				t.Fatal("missing per-item outcomes")
			}
		})
	}
}

func TestPaperlessCapacityWaitingDoesNotFinishOrFailStep(t *testing.T) {
	jobs := &mockJobs{work: m.PaperlessWork{Run: m.PaperlessRun{State: "running", Stage: "importing"}, Waiting: true}}
	service := NewPaperlessJobsService(jobs, nil, paperlessTestAuthority{})
	for range 20 {
		if done, err := service.Step(t.Context(), "run"); done || err != nil {
			t.Fatalf("capacity wait finished or failed: %v %v", done, err)
		}
	}
	if jobs.state != "" {
		t.Fatal("waiting run was finalized")
	}
}
