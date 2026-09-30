//go:build integration

package datasources

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	scheduler "github.com/domabas/domabas/backend/internal/data/scheduler/datasources"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"sync"
	"testing"
	"time"
)

type thumbnailFixture struct {
	t             *testing.T
	source        *DocumentDataSource
	connection    *pgx.Conn
	account, user string
	configuration []byte
}

func newThumbnailFixture(t *testing.T) *thumbnailFixture {
	t.Helper()
	url := testdb.New(t)
	db, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(db.Close)
	if err = db.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	conn, err := pgx.Connect(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close(context.Background()) })
	sched := scheduler.NewSchedulerDataSource(db.Database(), 128, "http://ollama.test:11434")
	if err = sched.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	c := m.DefaultConfiguration()
	body, err := json.Marshal(c)
	if err != nil {
		t.Fatal(err)
	}
	f := &thumbnailFixture{t: t, source: NewDocumentIngestionDataSource(db.Database(), nil, sched), connection: conn, account: uuid.NewString(), user: uuid.NewString(), configuration: body}
	f.exec(`BEGIN`)
	f.exec(`INSERT INTO accounts(id,name) VALUES($1,'Thumbnails')`, f.account)
	f.exec(`INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,$2,'unused',$3)`, f.user, f.user+"@example.test", f.account)
	f.exec(`INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)`, f.account, f.user)
	f.exec(`COMMIT`)
	return f
}
func (f *thumbnailFixture) exec(sql string, args ...any) {
	f.t.Helper()
	if _, err := f.connection.Exec(f.t.Context(), sql, args...); err != nil {
		f.t.Fatal(err)
	}
}
func (f *thumbnailFixture) count(sql string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.connection.QueryRow(f.t.Context(), sql, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}
func (f *thumbnailFixture) add(index int) string {
	f.t.Helper()
	id := fmt.Sprintf("00000000-0000-4000-8000-%012d", index)
	hash := sha256.Sum256([]byte(id))
	f.exec(`INSERT INTO documents(id,account_id,title,description,created_at) VALUES($1,$2,'Thumbnail','',clock_timestamp())`, id, f.account)
	f.exec(`INSERT INTO document_files(account_id,document_id,uploader_id,original_filename,media_type,size,sha256,ingested_at,location) VALUES($1,$2,$3,'source.png','image/png',100,$4,clock_timestamp(),'final')`, f.account, id, f.user, hex.EncodeToString(hash[:]))
	f.exec(`INSERT INTO document_processing(account_id,document_id,generation,state,stage,configuration_revision,configuration,updated_at,split_pipeline) VALUES($1,$2,1,'ready','complete',1,$3,clock_timestamp(),false)`, f.account, id, f.configuration)
	return id
}
func (f *thumbnailFixture) scan() {
	f.t.Helper()
	if err := f.source.DiscoverThumbnails(f.t.Context()); err != nil {
		f.t.Fatal(err)
	}
}
func (f *thumbnailFixture) due() {
	f.exec(`UPDATE document_thumbnail_scan SET next_scan_at=clock_timestamp()-interval '1 second'`)
}
func (f *thumbnailFixture) claim() m.DocumentThumbnailJob {
	f.t.Helper()
	jobs, err := f.source.ClaimThumbnailRecords(f.t.Context(), "thumbnail-test")
	if err != nil || len(jobs) != 1 {
		f.t.Fatalf("claim=%+v %v", jobs, err)
	}
	return m.DocumentThumbnailJob(jobs[0])
}
func TestThumbnailDiscoveryBoundedCadenceAndDurableWrap(t *testing.T) {
	f := newThumbnailFixture(t)
	for i := 1; i <= 205; i++ {
		f.add(i)
	}
	var concurrent sync.WaitGroup
	for range 4 {
		concurrent.Go(func() {
			if err := f.source.DiscoverThumbnails(t.Context()); err != nil {
				t.Error(err)
			}
		})
	}
	concurrent.Wait()
	if got := f.count(`SELECT count(*) FROM document_thumbnail_jobs`); got != 100 {
		t.Fatalf("first globally gated page=%d", got)
	}
	f.scan()
	if got := f.count(`SELECT count(*) FROM document_thumbnail_jobs`); got != 100 {
		t.Fatalf("minute gate ignored: %d", got)
	}
	f.exec(`UPDATE document_thumbnail_jobs SET status='failed',retryable=false,failure_code='invalid_file'`)
	f.due()
	f.scan()
	f.due()
	f.scan()
	if got := f.count(`SELECT count(*) FROM document_thumbnail_jobs`); got != 205 {
		t.Fatalf("cursor skipped records after failed page: %d", got)
	}
	f.add(0)
	f.due()
	f.scan()
	if got := f.count(`SELECT count(*) FROM document_thumbnail_jobs`); got != 206 {
		t.Fatalf("wrapped cursor missed earlier insert: %d", got)
	}
	f.due()
	f.scan()
	if got := f.count(`SELECT count(*) FROM document_thumbnail_jobs`); got != 206 {
		t.Fatalf("terminal failure rediscovered: %d", got)
	}
}
func TestThumbnailPublicationFencesAndExecutionOwnership(t *testing.T) {
	f := newThumbnailFixture(t)
	id := f.add(1)
	f.scan()
	j := f.claim()
	if _, err := f.source.ThumbnailWorkRecord(t.Context(), j); err != nil {
		t.Fatal(err)
	}
	artifact := m.DocumentThumbnailContent{Descriptor: m.DocumentThumbnail{SourceSHA256: j.SourceSHA256, SHA256: fmt.Sprintf("%064d", 2), MediaType: "image/jpeg", Size: 3, Width: 1, Height: 1, RendererRevision: 1}, Bytes: []byte{1, 2, 3}}
	if err := f.source.PublishThumbnail(t.Context(), j, artifact); err != nil {
		t.Fatal(err)
	}
	if err := f.source.PublishThumbnail(t.Context(), j, artifact); err != nil {
		t.Fatal(err)
	}
	if got := f.count(`SELECT count(*) FROM document_thumbnails`); got != 1 {
		t.Fatalf("publication count %d", got)
	}
	if got := f.count(`SELECT count(*) FROM scheduler_requests WHERE state='active' AND workflow_id=$1`, j.WorkflowID); got != 1 {
		t.Fatal("publication released execution ownership")
	}
	f.exec(`DELETE FROM document_processing WHERE document_id=$1`, id)
	f.exec(`DELETE FROM document_files WHERE document_id=$1`, id)
	f.exec(`DELETE FROM documents WHERE id=$1`, id)
	if got := f.count(`SELECT count(*) FROM document_thumbnails`); got != 0 {
		t.Fatal("artifact survived document deletion")
	}
	if got := f.count(`SELECT count(*) FROM document_thumbnail_jobs WHERE id=$1 AND closed_at IS NULL`, j.ID); got != 1 {
		t.Fatal("deletion erased execution ownership")
	}
	if err := f.source.PublishThumbnail(t.Context(), j, artifact); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("deleted publication=%v", err)
	}
	if err := f.source.ResolveThumbnail(t.Context(), j, "test-run", true, false, time.Minute); err != nil {
		t.Fatal(err)
	}
	if got := f.count(`SELECT count(*) FROM document_thumbnail_jobs WHERE id=$1 AND closed_at IS NOT NULL`, j.ID); got != 1 {
		t.Fatal("execution closure not retained")
	}
}
func TestThumbnailTransientRecoveryRequiresClosureAndBackoff(t *testing.T) {
	f := newThumbnailFixture(t)
	f.add(1)
	f.scan()
	j := f.claim()
	if err := f.source.FinishThumbnail(t.Context(), j, m.DocumentThumbnailCompletion(m.DocumentThumbnailOutcome{FailureCode: "thumbnail_unavailable", Retryable: true})); err != nil {
		t.Fatal(err)
	}
	f.due()
	f.scan()
	if f.count(`SELECT count(*) FROM document_thumbnail_jobs`) != 1 {
		t.Fatal("retry started before closure")
	}
	if err := f.source.ResolveThumbnail(t.Context(), j, "first-run", true, false, time.Minute); err != nil {
		t.Fatal(err)
	}
	if got := f.count(`SELECT count(*) FROM document_thumbnail_jobs WHERE attempt=2 AND available_at>clock_timestamp()+interval '50 seconds'`); got != 1 {
		t.Fatal("retry cooldown missing")
	}
	jobs, err := f.source.ClaimThumbnailRecords(t.Context(), "thumbnail-test")
	if err != nil || len(jobs) != 0 {
		t.Fatalf("early retry admitted=%v %v", jobs, err)
	}
	f.exec(`UPDATE document_thumbnail_jobs SET available_at=clock_timestamp()-interval '1 second' WHERE attempt=2`)
	next := f.claim()
	if next.Attempt != 2 || next.WorkflowID == j.WorkflowID {
		t.Fatal("retry identity reused")
	}
	f.exec(`UPDATE document_files SET sha256=$2 WHERE document_id=$1`, next.DocumentID, fmt.Sprintf("%064d", 42))
	if _, err = f.source.ThumbnailWorkRecord(t.Context(), next); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("replaced source accepted: %v", err)
	}
}
func TestThumbnailAmbiguousStartMissingSafetyWindow(t *testing.T) {
	f := newThumbnailFixture(t)
	f.add(1)
	f.scan()
	j := f.claim()
	if err := f.source.ResolveThumbnail(t.Context(), j, "", false, true, time.Minute); err != nil {
		t.Fatal(err)
	}
	if f.count(`SELECT count(*) FROM document_thumbnail_jobs WHERE closed_at IS NULL`) != 1 {
		t.Fatal("recent permit declared closed")
	}
	f.exec(`UPDATE document_thumbnail_jobs SET admitted_at=$2,permit_end=$3,lease_until=$3 WHERE id=$1`, j.ID, time.Now().Add(-46*time.Minute), time.Now().Add(-16*time.Minute))
	jobs, err := f.source.ClaimThumbnailRecords(t.Context(), "thumbnail-test")
	if err != nil || len(jobs) != 0 {
		t.Fatalf("expired start delivery renewed: %v %v", jobs, err)
	}
	if err = f.source.ResolveThumbnail(t.Context(), j, "", false, true, time.Minute); err != nil {
		t.Fatal(err)
	}
	if f.count(`SELECT count(*) FROM document_thumbnail_jobs WHERE id=$1 AND closed_at IS NOT NULL`, j.ID) != 1 {
		t.Fatal("safe never-started job retained")
	}
}

func TestThumbnailAcceptedIntentSurvivesReindexAndUsesWorkerOnly(t *testing.T) {
	f := newThumbnailFixture(t)
	id := f.add(1)
	f.scan()
	f.exec(`UPDATE document_processing SET state='queued',stage='queued',generation=2 WHERE document_id=$1`, id)
	j := f.claim()
	if _, err := f.source.ThumbnailWorkRecord(t.Context(), j); err != nil {
		t.Fatalf("same original lost during reindex: %v", err)
	}
	if f.count(`SELECT count(*) FROM scheduler_request_resources WHERE workflow_id=$1 AND resource_id='worker'`, j.WorkflowID) != 1 || f.count(`SELECT count(*) FROM scheduler_request_resources WHERE workflow_id=$1`, j.WorkflowID) != 1 {
		t.Fatal("thumbnail reserved a model resource")
	}
	artifact := m.DocumentThumbnailContent{Descriptor: m.DocumentThumbnail{SourceSHA256: j.SourceSHA256, SHA256: fmt.Sprintf("%064d", 2), MediaType: "image/jpeg", Size: 3, Width: 1, Height: 1, RendererRevision: 1}, Bytes: []byte{1, 2, 3}}
	if err := f.source.PublishThumbnail(t.Context(), j, artifact); err != nil {
		t.Fatal(err)
	}
}

func TestThumbnailPublicationDoesNotInvertDeletionLocks(t *testing.T) {
	f := newThumbnailFixture(t)
	id := f.add(1)
	f.scan()
	job := f.claim()
	if _, err := f.source.ThumbnailWorkRecord(t.Context(), job); err != nil {
		t.Fatal(err)
	}
	deletion, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer deletion.Rollback(context.Background())
	if err = lockDocument(t.Context(), deletion, f.account, id); err != nil {
		t.Fatal(err)
	}
	artifact := m.DocumentThumbnailContent{Descriptor: m.DocumentThumbnail{SourceSHA256: job.SourceSHA256, SHA256: fmt.Sprintf("%064d", 2), MediaType: "image/jpeg", Size: 3, Width: 1, Height: 1, RendererRevision: 1}, Bytes: []byte{1, 2, 3}}
	operation, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	result := make(chan error, 1)
	go func() { result <- f.source.PublishThumbnail(operation, job, artifact) }()
	deadline := time.Now().Add(3 * time.Second)
	for {
		var waiting bool
		err = f.source.database.QueryRow(t.Context(), `SELECT EXISTS(SELECT 1 FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid WHERE l.relation='documents'::regclass AND a.wait_event_type='Lock')`).Scan(&waiting)
		if err != nil {
			t.Fatal(err)
		}
		if waiting {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("publication never reached document lock")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if _, err = deletion.Exec(t.Context(), `SET LOCAL lock_timeout='250ms'`); err != nil {
		t.Fatal(err)
	}
	var document string
	if err = deletion.QueryRow(t.Context(), `SELECT document_id::text FROM document_files WHERE account_id=$1 AND document_id=$2 FOR UPDATE`, f.account, id).Scan(&document); err != nil {
		t.Fatalf("publication held file while waiting for document: %v", err)
	}
	for _, query := range []string{`DELETE FROM document_processing WHERE document_id=$1`, `DELETE FROM document_files WHERE document_id=$1`, `DELETE FROM documents WHERE id=$1`} {
		if _, err = deletion.Exec(t.Context(), query, id); err != nil {
			t.Fatal(err)
		}
	}
	if err = deletion.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err = <-result; !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("publication after concurrent deletion: %v", err)
	}
}

func TestThumbnailReadBindsExpectedOutputHashAndCurrentOriginal(t *testing.T) {
	f := newThumbnailFixture(t)
	id := f.add(1)
	f.scan()
	job := f.claim()
	if _, err := f.source.ThumbnailWorkRecord(t.Context(), job); err != nil {
		t.Fatal(err)
	}
	output := fmt.Sprintf("%064d", 2)
	artifact := m.DocumentThumbnailContent{Descriptor: m.DocumentThumbnail{SourceSHA256: job.SourceSHA256, SHA256: output, MediaType: "image/jpeg", Size: 3, Width: 1, Height: 1, RendererRevision: 1}, Bytes: []byte{1, 2, 3}}
	if err := f.source.PublishThumbnail(t.Context(), job, artifact); err != nil {
		t.Fatal(err)
	}
	actor := m.DocumentActor{AccountID: f.account}
	record, err := f.source.ReadThumbnailRecord(t.Context(), actor, id, output)
	if err != nil || len(record.Bytes) != 3 {
		t.Fatalf("current thumbnail unavailable: %v", err)
	}
	if _, err = f.source.ReadThumbnailRecord(t.Context(), actor, id, fmt.Sprintf("%064d", 3)); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("stale expected output accepted: %v", err)
	}
	if _, err = f.source.ReadThumbnailRecord(t.Context(), m.DocumentActor{AccountID: uuid.NewString()}, id, output); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("cross-namespace artifact exposed: %v", err)
	}
	f.exec(`UPDATE document_files SET sha256=$2 WHERE document_id=$1`, id, fmt.Sprintf("%064d", 4))
	if _, err = f.source.ReadThumbnailRecord(t.Context(), actor, id, output); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("replaced original exposed old thumbnail: %v", err)
	}
}
