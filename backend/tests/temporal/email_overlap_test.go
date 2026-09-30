//go:build temporal

package temporal_test

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	emailworkflows "github.com/domabas/domabas/backend/internal/domain/email/workflows"

	documentbootstrap "github.com/domabas/domabas/backend/internal/bootstrap/document"

	identitybootstrap "github.com/domabas/domabas/backend/internal/bootstrap/identity"

	emailsources "github.com/domabas/domabas/backend/internal/data/email/datasources"
	"github.com/domabas/domabas/backend/internal/data/email/datasources/credentials"

	emailrepos "github.com/domabas/domabas/backend/internal/data/email/repos"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulersources "github.com/domabas/domabas/backend/internal/data/scheduler/datasources"

	temporaldata "github.com/domabas/domabas/backend/internal/data/temporal"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"

	documentservices "github.com/domabas/domabas/backend/internal/domain/document/services"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	emailservices "github.com/domabas/domabas/backend/internal/domain/email/services"

	emailtemporal "github.com/domabas/domabas/backend/internal/data/email/temporal"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	enumspb "go.temporal.io/api/enums/v1"

	historypb "go.temporal.io/api/history/v1"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/client"

	temporallog "go.temporal.io/sdk/log"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

const overlapOriginal = "Subject: private overlap message\r\nFrom: sender@example.test\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nExact retained private body\r\n"

type overlapAttempt struct {
	reservation d.DocumentUploadReservation
	authority   d.DocumentImportAuthority
	accepted    d.DocumentImportResult
}

type overlapRejection struct{ accept, checkpoint, finish error }

type overlapPollService struct {
	source   *emailsources.EmailDataSource
	polling  *emailservices.EmailPollingService
	imports  *documentservices.DocumentImportService
	entered  chan overlapAttempt
	accepted chan overlapAttempt
	release  <-chan struct{}
	finish   <-chan struct{}
	rejected chan overlapRejection
}

func (s *overlapPollService) Page(ctx context.Context, attempt m.EmailAttempt) (m.EmailPageResult, error) {
	work, err := s.polling.ClaimAttempt(ctx, attempt)
	if err != nil {
		return m.EmailPageResult{}, err
	}
	attempt = work.Attempt
	cursor, err := s.polling.SetupMailbox(ctx, attempt, m.EmailMailbox{UIDValidity: 1, UIDNext: 2})
	if err != nil {
		return m.EmailPageResult{}, err
	}
	items, err := s.polling.PendingItems(ctx, attempt, 1, time.Now().Add(-24*time.Hour))
	if err != nil {
		return m.EmailPageResult{}, err
	}
	if len(items) == 0 {
		items, err = s.polling.DiscoverItems(ctx, attempt, false, 1, []int64{1})
	}
	if err != nil || len(items) != 1 {
		return m.EmailPageResult{}, fmt.Errorf("prepare overlap item: count=%d: %w", len(items), err)
	}
	item := items[0]
	part, err := s.source.Part(ctx, attempt, item, "0", "email.eml", "message/rfc822")
	if err != nil {
		return m.EmailPageResult{}, err
	}
	authority := d.DocumentImportAuthority{ProviderID: work.Provider.ID, OwnerID: work.Provider.OwnerID, AccountID: work.Provider.AccountID, RunID: work.Run.ID, MessageID: item.ID, PartID: part.ID, AttemptToken: attempt.Token, WorkflowRunID: attempt.WorkflowRunID, ActivityID: attempt.ActivityID, ProviderRevision: work.Provider.Revision, SourceGeneration: work.Provider.SourceGeneration, MailboxGeneration: cursor.MailboxGeneration, PageIndex: attempt.PageIndex, ActivityAttempt: attempt.Number, AttemptDeadline: attempt.Deadline}
	reservation, err := s.imports.Reserve(ctx, authority)
	if err != nil {
		return m.EmailPageResult{}, err
	}
	metadata, err := s.imports.Stage(ctx, authority, reservation, "email.eml", strings.NewReader(overlapOriginal))
	if err != nil {
		return m.EmailPageResult{}, err
	}
	if attempt.Number == 1 {
		s.entered <- overlapAttempt{reservation: reservation, authority: authority}
		<-s.release
		resumed, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_, acceptErr := s.imports.Accept(resumed, authority, reservation, metadata)
		checkpointErr := s.polling.MessageOutcome(resumed, attempt, item, "failed", "old_attempt", nil)
		finishErr := s.polling.Finish(resumed, attempt, false, "old_attempt")
		s.rejected <- overlapRejection{accept: acceptErr, checkpoint: checkpointErr, finish: finishErr}
		return m.EmailPageResult{}, nil
	}
	if attempt.Number != 2 {
		return m.EmailPageResult{}, fmt.Errorf("unexpected overlap attempt %d", attempt.Number)
	}
	accepted, err := s.imports.Accept(ctx, authority, reservation, metadata)
	if err != nil {
		return m.EmailPageResult{}, err
	}
	if err := s.polling.InspectionOutcome(ctx, attempt, item, true, false); err != nil {
		return m.EmailPageResult{}, err
	}
	s.accepted <- overlapAttempt{reservation: reservation, authority: authority, accepted: accepted}
	select {
	case <-s.finish:
	case <-ctx.Done():
		return m.EmailPageResult{}, ctx.Err()
	}
	if err := s.polling.Finish(ctx, attempt, false, ""); err != nil {
		return m.EmailPageResult{}, err
	}
	return m.EmailPageResult{}, nil
}

func (s *overlapPollService) Fail(ctx context.Context, attempt m.EmailAttempt, code string) error {
	return s.polling.Fail(ctx, attempt, code)
}

func TestEmailRealOverlappingAttemptsRetainOneOriginalAndReplay(t *testing.T) {
	address, namespace, processor := os.Getenv("TEMPORAL_ADDRESS"), os.Getenv("TEMPORAL_NAMESPACE"), os.Getenv("DOCUMENT_PROCESSOR_URL")
	if address == "" || namespace == "" || processor == "" {
		t.Fatal("TEMPORAL_ADDRESS, TEMPORAL_NAMESPACE and DOCUMENT_PROCESSOR_URL are required")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 3*time.Minute)
	defer cancel()
	databaseURL := testdb.New(t)
	database, err := postgres.NewPostgresDataSource(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	if err := database.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	identities, err := identitybootstrap.NewIdentityContainer(database.Database(), time.Now)
	if err != nil {
		t.Fatal(err)
	}
	session, err := identities.Service().Register(ctx, "Overlap test library", "overlap@example.test", "Overlap strong test password 2026!")
	if err != nil {
		t.Fatal(err)
	}
	principal := session.Identity
	actor := m.EmailActor{AccountID: principal.AccountID, UserID: principal.UserID, SessionDigest: principal.SessionDigest, CredentialRevision: principal.CredentialRevision}
	documentActor := d.DocumentActor{AccountID: actor.AccountID, UserID: actor.UserID, SessionDigest: actor.SessionDigest, CredentialRevision: actor.CredentialRevision}
	scheduler := schedulersources.NewSchedulerDataSource(database.Database(), 512, "http://ollama.test:11434")
	if err := scheduler.Initialize(ctx); err != nil {
		t.Fatal(err)
	}
	storage := t.TempDir()
	documents, err := documentbootstrap.NewDocumentContainer(ctx, database.Database(), identities.Service(), documentbootstrap.DocumentOptions{Scheduler: scheduler, IngestionRoot: filepath.Join(storage, "ingestion"), StorageRoot: filepath.Join(storage, "documents"), ProcessorURL: processor}, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer documents.Close()
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	encoded, err := json.Marshal(map[string]string{"test": base64.StdEncoding.EncodeToString(key)})
	clear(key)
	if err != nil {
		t.Fatal(err)
	}
	vault, err := credentials.NewEmailCredentialKeyring(string(encoded), "test")
	if err != nil {
		t.Fatal(err)
	}
	source := emailsources.NewEmailDataSource(database.Database(), scheduler)
	repository := emailrepos.NewEmailRepository(source, vault)
	emailService := emailservices.NewEmailService(repository, nil, vault.Available(), identities.Service())
	pollingRepository := emailrepos.NewEmailPollingRepository(source, vault)
	polling := emailservices.NewEmailPollingService(pollingRepository, pollingRepository, nil, documents.Importer(), time.Now, identities.Service())
	username, password := "private-user@example.test", "private-mail-password"
	provider, err := emailService.Create(ctx, actor, m.EmailProviderInput{ID: uuid.NewString(), EmailSettings: m.EmailSettings{Label: "Overlap mailbox", Host: "example.test", Port: 993, Mailbox: "INBOX", Enabled: true, IntervalMinutes: 15, MaxAgeDays: 30, PageSize: 1}, Username: &username, Password: &password})
	if err != nil {
		t.Fatal(err)
	}
	run, err := emailService.Start(ctx, actor, provider.ID, m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: provider.Revision})
	if err != nil {
		t.Fatal(err)
	}
	queue := "domabas-email-overlap-" + uuid.NewString()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	remote, err := temporaldata.NewTemporalDataSource(ctx, address, namespace, logger)
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	release := make(chan struct{})
	finish := make(chan struct{})
	var releaseOnce sync.Once
	var finishOnce sync.Once
	resume := func() { releaseOnce.Do(func() { close(release) }) }
	complete := func() { finishOnce.Do(func() { close(finish) }) }
	service := &overlapPollService{source: source, polling: polling, imports: documents.Importer(), entered: make(chan overlapAttempt, 1), accepted: make(chan overlapAttempt, 1), release: release, finish: finish, rejected: make(chan overlapRejection, 1)}
	firstActivities := emailtemporal.NewEmailPollActivities(service, remote.Client())
	secondActivities := emailtemporal.NewEmailPollActivities(service, remote.Client())
	first := worker.New(remote.Client(), queue, worker.Options{MaxConcurrentActivityExecutionSize: 1, WorkerStopTimeout: time.Second, Identity: "first-" + queue})
	second := worker.New(remote.Client(), queue, worker.Options{MaxConcurrentActivityExecutionSize: 1, WorkerStopTimeout: time.Second, Identity: "second-" + queue})
	for _, registration := range []struct {
		worker     worker.Worker
		activities *emailtemporal.EmailPollActivities
	}{{first, firstActivities}, {second, secondActivities}} {
		registration.worker.RegisterWorkflowWithOptions(emailworkflows.EmailPollWorkflow, workflow.RegisterOptions{Name: emailworkflows.EmailPollWorkflowName})
		registration.worker.RegisterActivityWithOptions(registration.activities.Page, activity.RegisterOptions{Name: emailworkflows.EmailPollPageActivityName})
	}
	firstStarted, firstStopped, secondStarted := false, false, false
	var execution client.WorkflowRun
	defer func() {
		resume()
		complete()
		if firstStarted && !firstStopped {
			first.Stop()
		}
		if secondStarted {
			second.Stop()
		}
		firstActivities.Close()
		secondActivities.Close()
		if execution != nil {
			cleanup, stop := context.WithTimeout(context.Background(), 10*time.Second)
			defer stop()
			info, err := remote.Client().DescribeWorkflowExecution(cleanup, execution.GetID(), execution.GetRunID())
			if err != nil {
				t.Errorf("inspect owned email cleanup: %v", err)
			} else if info.GetWorkflowExecutionInfo().GetStatus() == enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING {
				if err := remote.Client().TerminateWorkflow(cleanup, execution.GetID(), execution.GetRunID(), "owned email overlap test cleanup"); err != nil {
					t.Errorf("terminate owned email workflow: %v", err)
				}
			}
		}
	}()
	if err := first.Start(); err != nil {
		t.Fatal(err)
	}
	firstStarted = true
	lease, err := polling.ClaimDelivery(ctx, queue)
	if err != nil || lease == nil || lease.RunID != run.ID {
		t.Fatalf("claim owned email delivery: %+v %v", lease, err)
	}
	start, stop := context.WithDeadline(ctx, lease.LatestPermitEnd)
	execution, err = remote.Client().ExecuteWorkflow(start, client.StartWorkflowOptions{ID: lease.WorkflowID, TaskQueue: queue, WorkflowExecutionTimeout: 10 * time.Minute, WorkflowIDReusePolicy: enumspb.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE}, emailworkflows.EmailPollWorkflowName, emailworkflows.EmailPollWorkflowInput{RunID: run.ID})
	stop()
	if err != nil {
		t.Fatal(err)
	}
	if err := polling.AcknowledgeDelivery(ctx, *lease, execution.GetRunID()); err != nil {
		t.Fatal(err)
	}
	var old overlapAttempt
	select {
	case old = <-service.entered:
	case <-ctx.Done():
		t.Fatal("first real activity did not stage its original")
	}
	first.Stop()
	firstStopped = true
	if err := second.Start(); err != nil {
		t.Fatal(err)
	}
	secondStarted = true
	var current overlapAttempt
	select {
	case current = <-service.accepted:
	case <-ctx.Done():
		t.Fatal("second worker did not supersede the stalled attempt")
	}
	if old.reservation.ID == current.reservation.ID || old.authority.AttemptToken == current.authority.AttemptToken || current.authority.ActivityAttempt != 2 {
		t.Fatal("attempts shared staging or durable ownership")
	}
	resume()
	select {
	case rejected := <-service.rejected:
		if !errors.Is(rejected.accept, d.ErrStaleJob) || !errors.Is(rejected.checkpoint, m.ErrStaleAttempt) || !errors.Is(rejected.finish, m.ErrStaleAttempt) {
			t.Fatalf("old attempt mutation fences: accept=%v checkpoint=%v finish=%v", rejected.accept, rejected.checkpoint, rejected.finish)
		}
	case <-ctx.Done():
		t.Fatal("old attempt did not resume")
	}
	complete()
	if err := execution.Get(ctx, nil); err != nil {
		t.Fatal(err)
	}
	if err := documents.Ingestion().AbandonUpload(ctx, documentActor, old.reservation); err != nil {
		t.Fatal(err)
	}
	content, err := documents.Ingestion().OpenContent(ctx, documentActor, current.accepted.DocumentID)
	if err != nil {
		t.Fatal(err)
	}
	bytes, readErr := io.ReadAll(content.Reader)
	closeErr := content.Reader.Close()
	if readErr != nil || closeErr != nil || string(bytes) != overlapOriginal {
		t.Fatalf("old-attempt cleanup damaged accepted bytes: %v %v", readErr, closeErr)
	}
	connection, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	var count, acceptedCount int
	var status string
	if err := connection.QueryRow(ctx, `SELECT (SELECT count(*) FROM documents WHERE account_id=$1),messages_accepted,status FROM email_runs WHERE id=$2`, actor.AccountID, run.ID).Scan(&count, &acceptedCount, &status); err != nil || count != 1 || acceptedCount != 1 || status != "succeeded" {
		t.Fatalf("duplicate acceptance or outcome mutation: count=%d accepted=%d status=%s err=%v", count, acceptedCount, status, err)
	}
	history := &historypb.History{}
	iterator := remote.Client().GetWorkflowHistory(ctx, execution.GetID(), execution.GetRunID(), false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT)
	for iterator.HasNext() {
		event, err := iterator.Next()
		if err != nil {
			t.Fatal(err)
		}
		history.Events = append(history.Events, event)
		if start := event.GetWorkflowExecutionStartedEventAttributes(); start != nil {
			payloads := start.GetInput().GetPayloads()
			var fields map[string]any
			if len(payloads) != 1 || json.Unmarshal(payloads[0].GetData(), &fields) != nil || len(fields) != 1 || fields["runId"] != run.ID {
				t.Fatal("email workflow history input is not the owned run ID alone")
			}
		}
		for _, secret := range []string{username, password, "private overlap message", "Exact retained private body", storage} {
			if strings.Contains(event.String(), secret) {
				t.Fatal("private email content entered workflow history")
			}
		}
	}
	replayer := worker.NewWorkflowReplayer()
	replayer.RegisterWorkflowWithOptions(emailworkflows.EmailPollWorkflow, workflow.RegisterOptions{Name: emailworkflows.EmailPollWorkflowName})
	if err := replayer.ReplayWorkflowHistory(temporallog.NewStructuredLogger(logger), history); err != nil {
		t.Fatalf("real email history did not replay: %v", err)
	}
}
