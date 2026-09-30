package services

import (
	"context"
	"fmt"
	"io"
	"reflect"
	"testing"
	"time"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type emailDiscoveryRepository struct {
	p.EmailPollingRepository
	cursor    m.EmailCursor
	uids      []int64
	finished  bool
	backfills []bool
	skipped   int
}

func (*emailDiscoveryRepository) ClaimAttempt(_ context.Context, attempt m.EmailAttempt, _ m.EmailAttemptAdmission) (m.EmailWork, error) {
	return m.EmailWork{Attempt: attempt, Provider: m.EmailProvider{EmailSettings: m.EmailSettings{PageSize: 2, MaxAgeDays: 30}}}, nil
}
func (r *emailDiscoveryRepository) SetupMailbox(context.Context, m.EmailAttempt, m.EmailMailboxCommand) (m.EmailCursor, error) {
	return r.cursor, nil
}
func (*emailDiscoveryRepository) PendingItems(context.Context, m.EmailAttempt, m.EmailPendingQuery) ([]m.EmailItem, error) {
	return nil, nil
}
func (r *emailDiscoveryRepository) DiscoverItems(_ context.Context, _ m.EmailAttempt, command m.EmailDiscoveryCommand) ([]m.EmailItem, error) {
	backfill, through, uids := command.Backfill, command.Through, command.UIDs
	r.backfills = append(r.backfills, backfill)
	r.uids = append(r.uids, uids...)
	if backfill {
		r.cursor.BackfillNext = through + 1
	} else {
		r.cursor.LiveNext = through + 1
	}
	var items []m.EmailItem
	for _, uid := range uids {
		items = append(items, m.EmailItem{ID: fmt.Sprint(uid), UID: uid})
	}
	return items, nil
}
func (*emailDiscoveryRepository) Part(context.Context, m.EmailAttempt, m.EmailItem, string, string, string) (m.EmailPart, error) {
	return m.EmailPart{ID: "original"}, nil
}
func (*emailDiscoveryRepository) SetStage(context.Context, m.EmailAttempt, string) error { return nil }
func (r *emailDiscoveryRepository) MessageOutcome(_ context.Context, _ m.EmailAttempt, _ m.EmailItem, command m.EmailMessageOutcomeCommand) error {
	if command.State == "skipped" && command.Code == "age_excluded" {
		r.skipped++
	}
	return nil
}
func (*emailDiscoveryRepository) InspectionOutcome(context.Context, m.EmailAttempt, m.EmailItem, m.EmailInspectionCommand) error {
	return nil
}
func (r *emailDiscoveryRepository) HasMore(context.Context, m.EmailAttempt) (bool, error) {
	return r.cursor.LiveNext <= r.cursor.LiveUpper || r.cursor.BackfillNext > 0 && r.cursor.BackfillNext <= r.cursor.BackfillUpper, nil
}
func (r *emailDiscoveryRepository) Finish(context.Context, m.EmailRunFinishCommand) error {
	r.finished = true
	return nil
}

type emailDiscoverySession struct {
	p.EmailMailboxSession
	uids   []int64
	cutoff time.Time
	date   time.Time
}

func (*emailDiscoverySession) Info() m.EmailMailbox {
	return m.EmailMailbox{UIDValidity: 7, UIDNext: 4000000001}
}
func (*emailDiscoverySession) Close() error { return nil }
func (s *emailDiscoverySession) Discover(_ context.Context, from, through int64, since time.Time) (m.EmailDiscovery, error) {
	s.cutoff = since
	result := m.EmailDiscovery{Through: through}
	for _, uid := range s.uids {
		if uid >= from && uid <= through {
			result.UIDs = append(result.UIDs, uid)
		}
	}
	return result, nil
}
func (s *emailDiscoverySession) Fetch(_ context.Context, uid int64, consume func(m.EmailMessage) error) (m.EmailMessage, error) {
	message := m.EmailMessage{UID: uid, InternalDate: time.Now()}
	if !s.date.IsZero() {
		message.InternalDate = s.date
	}
	return message, consume(message)
}

type emailDiscoveryGateway struct{ session p.EmailMailboxSession }

func (g emailDiscoveryGateway) Connect(context.Context, m.EmailConnection) (p.EmailMailboxSession, error) {
	return g.session, nil
}

type emailDiscoveryImporter struct{ accepted int }

func (*emailDiscoveryImporter) Reserve(context.Context, d.DocumentImportAuthority) (d.DocumentUploadReservation, error) {
	return d.DocumentUploadReservation{}, nil
}
func (*emailDiscoveryImporter) Stage(context.Context, d.DocumentImportAuthority, d.DocumentUploadReservation, string, io.Reader) (d.DocumentMetadata, error) {
	return d.DocumentMetadata{}, nil
}
func (i *emailDiscoveryImporter) Accept(context.Context, d.DocumentImportAuthority, d.DocumentUploadReservation, d.DocumentMetadata) (d.DocumentImportResult, error) {
	i.accepted++
	return d.DocumentImportResult{DocumentID: "accepted"}, nil
}
func (*emailDiscoveryImporter) Inspect(context.Context, d.DocumentImportAuthority, func(d.DocumentEmailPart) error) (d.DocumentEmailInspection, error) {
	return d.DocumentEmailInspection{}, nil
}

func TestEmailSparseDiscoveryImportsAndTruncatesAtLastSelectedUID(t *testing.T) {
	repository := &emailDiscoveryRepository{cursor: m.EmailCursor{LiveNext: 1, LiveUpper: 4000000000}}
	session := &emailDiscoverySession{uids: []int64{2000000000, 3000000000, 4000000000}}
	importer := &emailDiscoveryImporter{}
	now := time.Now()
	service := NewEmailPollingService(repository, nil, emailDiscoveryGateway{session}, importer, func() time.Time { return now }, emailTestAuthority{})
	page, err := service.Page(t.Context(), m.EmailAttempt{Token: "test", Number: 1, ActivityID: "activity", WorkflowRunID: "workflow"})
	if err != nil || !page.HasMore || repository.cursor.LiveNext != 3000000001 || importer.accepted != 2 || repository.finished {
		t.Fatalf("first page: %+v cursor=%+v imported=%d err=%v", page, repository.cursor, importer.accepted, err)
	}
	page, err = service.Page(t.Context(), m.EmailAttempt{PageIndex: 1, Token: "test", Number: 1, ActivityID: "activity", WorkflowRunID: "workflow"})
	if err != nil || page.HasMore || !repository.finished || importer.accepted != 3 || !reflect.DeepEqual(repository.uids, session.uids) {
		t.Fatalf("continuation skipped imports: %+v uids=%v imported=%d err=%v", page, repository.uids, importer.accepted, err)
	}
	if !session.cutoff.Equal(now.UTC().AddDate(0, 0, -30)) {
		t.Fatal("age cutoff changed")
	}
}
func TestEmailSparseDiscoveryPreservesBackfillAndLiveCursors(t *testing.T) {
	repository := &emailDiscoveryRepository{cursor: m.EmailCursor{LiveNext: 3000000001, LiveUpper: 4000000000, BackfillNext: 1, BackfillUpper: 3000000000, BackfillTurn: true}}
	session := &emailDiscoverySession{uids: []int64{2000000000, 3000000000, 4000000000}}
	importer := &emailDiscoveryImporter{}
	service := NewEmailPollingService(repository, nil, emailDiscoveryGateway{session}, importer, time.Now, emailTestAuthority{})
	if _, err := service.Page(t.Context(), m.EmailAttempt{Token: "test", Number: 1, ActivityID: "activity", WorkflowRunID: "workflow"}); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(repository.backfills, []bool{true}) || repository.cursor.LiveNext != 3000000001 || repository.cursor.BackfillNext != 3000000001 || importer.accepted != 2 {
		t.Fatalf("backfill changed live progress: %+v", repository)
	}
}

func TestEmailSparseDiscoveryStillEnforcesExactInternalDate(t *testing.T) {
	now := time.Now()
	for _, delta := range []time.Duration{-time.Second, 0} {
		t.Run(delta.String(), func(t *testing.T) {
			repository := &emailDiscoveryRepository{cursor: m.EmailCursor{LiveNext: 1, LiveUpper: 4000000000}}
			session := &emailDiscoverySession{uids: []int64{2000000000}, date: now.UTC().AddDate(0, 0, -30).Add(delta)}
			importer := &emailDiscoveryImporter{}
			service := NewEmailPollingService(repository, nil, emailDiscoveryGateway{session}, importer, func() time.Time { return now }, emailTestAuthority{})
			if _, err := service.Page(t.Context(), m.EmailAttempt{Token: "test", Number: 1, ActivityID: "activity", WorkflowRunID: "workflow"}); err != nil {
				t.Fatal(err)
			}
			if delta < 0 && (importer.accepted != 0 || repository.skipped != 1) || delta == 0 && (importer.accepted != 1 || repository.skipped != 0) {
				t.Fatalf("exact cutoff changed: imports=%d skipped=%d", importer.accepted, repository.skipped)
			}
		})
	}
}

func (r *emailDiscoveryRepository) FinishFacts(_ context.Context, attempt m.EmailAttempt) (m.EmailRunFinishFacts, error) {
	return m.EmailRunFinishFacts{Work: m.EmailWork{Attempt: attempt}}, nil
}

func (r *emailDiscoveryRepository) MailboxFacts(context.Context, m.EmailAttempt) (m.EmailMailboxFacts, error) {
	return m.EmailMailboxFacts{Exists: true, Cursor: r.cursor}, nil
}

func (*emailDiscoveryRepository) MessageFacts(context.Context, m.EmailAttempt, m.EmailItem) (m.EmailMessageFacts, error) {
	return m.EmailMessageFacts{}, nil
}
