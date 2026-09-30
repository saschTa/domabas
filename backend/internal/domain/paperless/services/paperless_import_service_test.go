package services

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/paperless/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type mockRepository struct {
	p.PaperlessRepository
	original m.PaperlessOriginal
	err      error
	page     m.PaperlessPage
}

func (r *mockRepository) Original(context.Context, m.PaperlessConnection, int64) (m.PaperlessOriginal, error) {
	return r.original, r.err
}
func (r *mockRepository) Preview(context.Context, m.PaperlessConnection, int) (m.PaperlessPage, error) {
	return r.page, r.err
}

type mockImporter struct {
	p.PaperlessDocumentImporter
	acceptError         error
	abandoned, accepted bool
	actor               d.DocumentActor
}

func (r *mockImporter) ReserveUpload(_ context.Context, a d.DocumentActor) (d.DocumentUploadReservation, error) {
	r.actor = a
	return d.DocumentUploadReservation{ID: "reservation"}, nil
}
func (r *mockImporter) StageUpload(_ context.Context, _ d.DocumentActor, _ d.DocumentUploadReservation, _ string, body io.Reader) (d.DocumentFileReference, error) {
	_, err := io.ReadAll(body)
	return d.DocumentFileReference{}, err
}
func (r *mockImporter) AcceptUpload(context.Context, d.DocumentActor, d.DocumentUploadReservation, d.DocumentMetadata) (d.Document, error) {
	r.accepted = true
	return d.Document{ID: "accepted"}, r.acceptError
}
func (r *mockImporter) AbandonUpload(context.Context, d.DocumentActor, d.DocumentUploadReservation) error {
	r.abandoned = true
	return nil
}
func TestImportReusesAcceptanceAndCleansDuplicates(t *testing.T) {
	for _, duplicate := range []bool{false, true} {
		t.Run(map[bool]string{true: "duplicate", false: "new"}[duplicate], func(t *testing.T) {
			documents := &mockImporter{}
			if duplicate {
				documents.acceptError = d.ErrDuplicate
			}
			repo := &mockRepository{original: m.PaperlessOriginal{Reader: io.NopCloser(strings.NewReader("original")), Filename: "paper.pdf", Metadata: d.DocumentMetadata{Title: "Paper"}}}
			result, err := NewPaperlessImportService(repo, documents).Import(t.Context(), d.DocumentActor{AccountID: "library", ImportRunID: "run"}, m.PaperlessConnection{}, 1)
			if err != nil || result.Duplicate != duplicate || !documents.accepted || documents.abandoned != duplicate || documents.actor.ImportRunID != "run" {
				t.Fatalf("result %+v, importer %+v, err %v", result, documents, err)
			}
		})
	}
}

type mockJobs struct {
	p.PaperlessJobsRepository
	work        m.PaperlessWork
	err         error
	state, code string
	outcome     m.PaperlessOutcome
	pageCalls   int
}

func (j *mockJobs) Work(context.Context, string, m.PaperlessWorkCommand) (m.PaperlessWork, error) {
	return j.work, j.err
}
func (j *mockJobs) ReleaseClaims(context.Context, string, []m.PaperlessRetrieval) error { return nil }
func (j *mockJobs) RunActive(context.Context, string) (bool, error)                     { return true, nil }
func (j *mockJobs) Finish(_ context.Context, _ string, command m.PaperlessTerminalCommand) error {
	j.state, j.code = command.State, command.Code
	return nil
}
func (j *mockJobs) RecordPage(context.Context, string, m.PaperlessPageCommand) error {
	j.pageCalls++
	return nil
}
func (j *mockJobs) RecordOutcome(_ context.Context, _ string, o m.PaperlessOutcome) error {
	j.outcome = o
	return nil
}
func TestPipelineCheckpointsCancellationRevocationAndFailures(t *testing.T) {
	for _, code := range []string{"invalid_metadata", "source_unavailable", "source_unauthorized"} {
		repo := &mockRepository{err: m.PaperlessFailure{Code: code}}
		store := &mockJobs{work: m.PaperlessWork{Actor: d.DocumentActor{ImportRunID: "run"}, Run: m.PaperlessRun{State: "running", Stage: "importing"}, Items: []m.PaperlessRetrieval{{Document: m.PaperlessDocument{ID: 1, Title: "Test"}, Deadline: time.Now().Add(time.Minute)}}}}
		jobs := NewPaperlessJobsService(store, NewPaperlessImportService(repo, &mockImporter{}), paperlessTestAuthority{})
		done, err := jobs.Step(t.Context(), "run")
		switch code {
		case "invalid_metadata":
			if done || err != nil || store.outcome.Status != "failed" {
				t.Fatal(done, err, store)
			}
		case "source_unavailable":
			if done || err == nil || store.state != "" {
				t.Fatal(done, err, store)
			}
		case "source_unauthorized":
			if !done || err != nil || store.state != "failed" {
				t.Fatal(done, err, store)
			}
		}
	}
	for _, cancelled := range []bool{false, true} {
		store := &mockJobs{work: m.PaperlessWork{Run: m.PaperlessRun{State: "running", CancelRequested: cancelled}}}
		if !cancelled {
			store.err = d.ErrForbidden
		}
		done, err := NewPaperlessJobsService(store, nil, paperlessTestAuthority{}).Step(t.Context(), "run")
		if !done || err != nil || (!cancelled && store.code != "permission_revoked") || (cancelled && store.state != "cancelled") {
			t.Fatal(done, err, store)
		}
	}
	store := &mockJobs{err: errors.New("database offline")}
	done, err := NewPaperlessJobsService(store, nil, paperlessTestAuthority{}).Step(t.Context(), "run")
	if done || err == nil {
		t.Fatal("transient storage failure became terminal")
	}
}

func TestDiscoveryContinuesPastOneHundredPages(t *testing.T) {
	repo := &mockRepository{page: m.PaperlessPage{Total: 10001, Items: []m.PaperlessDocument{{ID: 10001, Title: "Late source document"}}}}
	page, err := NewPaperlessImportService(repo, nil).Preview(t.Context(), m.PaperlessConnection{}, 101)
	if err != nil || page.Total != 10001 || len(page.Items) != 1 {
		t.Fatal("large library discovery rejected", page, err)
	}
	if _, err := NewPaperlessImportService(repo, nil).Preview(t.Context(), m.PaperlessConnection{}, 0); err == nil {
		t.Fatal("invalid page accepted")
	}
}

func (j *mockJobs) PageFacts(context.Context, string) (m.PaperlessPageFacts, error) {
	return m.PaperlessPageFacts{Page: j.work.Page}, nil
}

func (j *mockJobs) RunFacts(context.Context, string) (m.PaperlessRunFacts, error) {
	return m.PaperlessRunFacts{State: j.work.Run.State, Stage: j.work.Run.Stage, Cancelled: j.work.Run.CancelRequested}, nil
}
