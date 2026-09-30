//go:build integration

package repos_test

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"
	"sync"
	"testing"
	"time"

	sources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	repos "github.com/domabas/domabas/backend/internal/data/document/repos"
	identitysources "github.com/domabas/domabas/backend/internal/data/identity/datasources"
	identityrepos "github.com/domabas/domabas/backend/internal/data/identity/repos"
	"github.com/domabas/domabas/backend/internal/data/identity/security"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulersources "github.com/domabas/domabas/backend/internal/data/scheduler/datasources"
	schedulerrepos "github.com/domabas/domabas/backend/internal/data/scheduler/repos"
	documentinterfaces "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/domain/document/services"
	identityservices "github.com/domabas/domabas/backend/internal/domain/identity/services"
	schedulermodels "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	schedulerservices "github.com/domabas/domabas/backend/internal/domain/scheduler/services"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type fixturePublication struct{}

func (fixturePublication) Promote(_ context.Context, ref records.DocumentContentReference) (records.DocumentContentReference, error) {
	ref.Location = "final"
	return ref, nil
}

type ingestionFixture struct {
	repository *repos.DocumentIngestionRepository
	service    *services.DocumentIngestionService
	authority  *identityservices.IdentityService
	documents  *repos.DocumentRepository
	connection *pgx.Conn
	actor      m.DocumentActor
	source     *postgres.PostgresDataSource
	scheduler  *schedulersources.SchedulerDataSource
}

func newIngestionFixture(t *testing.T, limits ...records.DocumentIngestionLimits) *ingestionFixture {
	t.Helper()
	url := testdb.New(t)
	source, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(source.Close)
	if err = source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { connection.Close(context.Background()) })
	policy, err := security.NewCasbinIdentityAuthorizer()
	if err != nil {
		t.Fatal(err)
	}
	scheduler := schedulersources.NewSchedulerDataSource(source.Database(), 512, "http://ollama.test:11434")
	if err := scheduler.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	data := sources.NewDocumentIngestionDataSource(source.Database(), fixturePublication{}, scheduler)
	if len(limits) > 0 {
		data = sources.NewDocumentLLMDataSource(source.Database(), fixturePublication{}, "", nil, scheduler, limits[0])
	}
	if err := initializeDocumentSource(t.Context(), data); err != nil {
		t.Fatal(err)
	}
	f := &ingestionFixture{repository: repos.NewDocumentIngestionRepository(data), documents: repos.NewDocumentRepository(data), connection: connection, source: source, scheduler: scheduler}
	f.authority = identityservices.NewIdentityService(identityrepos.NewIdentityRepository(identitysources.NewIdentityDataSource(source.Database())), nil, policy, time.Now, uuid.NewString)
	f.service = services.NewDocumentIngestionService(f.repository, nil, documentFixtureProcessor{}, f.authority, time.Now)
	f.actor = f.addActor(t)
	f.resourceCapacity(t, 10)
	if len(limits) > 0 {
		f.resourceCapacity(t, max(1, limits[0].Concurrency, limits[0].AIConcurrency))
	}
	return f
}
func (f *ingestionFixture) addActor(t *testing.T) m.DocumentActor {
	t.Helper()
	a := m.DocumentActor{AccountID: uuid.NewString(), UserID: uuid.NewString(), SessionDigest: strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", ""), CredentialRevision: 1}
	err := pgx.BeginFunc(t.Context(), f.connection, func(tx pgx.Tx) error {
		if _, e := tx.Exec(t.Context(), "INSERT INTO accounts(id,name) VALUES($1,'Upload test')", a.AccountID); e != nil {
			return e
		}
		if _, e := tx.Exec(t.Context(), "INSERT INTO users(id,email,password_hash,personal_account_id,system_role) VALUES($1,$2,'unused-test-hash',$3,'admin')", a.UserID, a.UserID+"@example.test", a.AccountID); e != nil {
			return e
		}
		if _, e := tx.Exec(t.Context(), "INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)", a.AccountID, a.UserID); e != nil {
			return e
		}
		_, e := tx.Exec(t.Context(), "INSERT INTO sessions(digest,account_id,user_id,credential_revision,expires_at) VALUES($1,$2,$3,1,clock_timestamp()+interval '1 hour')", a.SessionDigest, a.AccountID, a.UserID)
		return e
	})
	if err != nil {
		t.Fatal(err)
	}
	return a
}
func (f *ingestionFixture) stage(t *testing.T, a m.DocumentActor, hash string) m.DocumentUploadReservation {
	t.Helper()
	r, err := f.repository.Reserve(t.Context(), a, m.DocumentUploadReservation{ExpiresAt: time.Now().Add(5 * time.Minute), ID: uuid.NewString(), AccountID: a.AccountID, UploaderID: a.UserID})
	if err != nil {
		t.Fatal(err)
	}
	ref := m.DocumentFileReference{AccountID: a.AccountID, UploaderID: a.UserID, DocumentID: r.ID, Location: "staged", File: m.DocumentFile{OriginalFilename: "paper.pdf", MediaType: "application/pdf", Size: 123, SHA256: hash, UploaderID: a.UserID}}
	if err = f.repository.RecordStaged(t.Context(), a, r.ID, ref); err != nil {
		t.Fatal(err)
	}
	return r
}
func (f *ingestionFixture) accept(t *testing.T, a m.DocumentActor, hash, title string) m.Document {
	t.Helper()
	r := f.stage(t, a, hash)
	metadata, err := (m.DocumentMetadata{Title: title}).Normalize()
	if err != nil {
		t.Fatal(err)
	}
	doc, err := f.acceptReservation(t.Context(), a, r.ID, metadata, time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	f.exec(t, "UPDATE document_processing SET split_pipeline=false WHERE account_id=$1 AND document_id=$2", a.AccountID, doc.ID)
	return doc
}
func (f *ingestionFixture) exec(t *testing.T, query string, args ...any) {
	t.Helper()
	if _, err := f.connection.Exec(t.Context(), query, args...); err != nil {
		t.Fatal(err)
	}
}
func (f *ingestionFixture) ready(t *testing.T, doc m.Document, text string, vector []float64) m.DocumentJob {
	t.Helper()
	j := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
	f.admit(t, j)
	work, err := f.service.Work(t.Context(), j, "extracting")
	if err != nil {
		t.Fatal(err)
	}
	if err = f.service.SaveExtraction(t.Context(), j, 0, text); err != nil {
		t.Fatal(err)
	}
	if err = f.service.SaveEmbeddings(t.Context(), j, 1, m.DefaultConfiguration().EmbeddingSpace(), []m.DocumentChunk{{Text: text, Vector: vector}}); err != nil {
		t.Fatal(err)
	}
	work.Reference.Location = "final"
	if err = f.service.Publish(t.Context(), j, 1); err != nil {
		t.Fatal(err)
	}
	f.closeTerminal(t)
	return j
}
func unitVector(index int) []float64 {
	result := make([]float64, m.EmbeddingDimensions)
	result[index] = 1
	return result
}

func TestIngestionReservationsAuthorityDuplicatesAndReaping(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	a := f.actor
	hash := strings.Repeat("a", 64)
	r1, r2 := f.stage(t, a, hash), f.stage(t, a, hash)
	metadata, _ := (m.DocumentMetadata{Title: "Original", Tags: []string{" Mail ", "work"}, Kind: "letter"}).Normalize()
	var wait sync.WaitGroup
	results := make(chan error, 2)
	for _, reservation := range []m.DocumentUploadReservation{r1, r2} {
		wait.Go(func() {
			_, err := f.acceptReservation(ctx, a, reservation.ID, metadata, time.Now().UTC())
			results <- err
		})
	}
	wait.Wait()
	close(results)
	success, duplicate := 0, 0
	for err := range results {
		if err == nil {
			success++
		} else if errors.Is(err, m.ErrDuplicate) {
			duplicate++
		} else {
			t.Fatal(err)
		}
	}
	if success != 1 || duplicate != 1 {
		t.Fatalf("duplicate transaction outcomes %d/%d", success, duplicate)
	}
	var count int
	if err := f.connection.QueryRow(ctx, "SELECT count(*) FROM document_outbox").Scan(&count); err != nil || count != 1 {
		t.Fatalf("duplicate outbox persisted: %d %v", count, err)
	}
	page, err := f.documents.List(ctx, a.AccountID, m.DocumentPageRequest{Limit: 20})
	if err != nil || page.Total != 1 {
		t.Fatalf("documents: %+v %v", page, err)
	}
	doc := page.Items[0]
	if doc.File == nil || doc.Processing == nil || doc.Processing.State != "queued" || doc.Kind != "letter" || doc.Tags[0] != "mail" {
		t.Fatalf("missing metadata/file/processing: %+v", doc)
	}
	acceptedID := doc.ID
	for _, r := range []m.DocumentUploadReservation{r1, r2} {
		ref, err := f.repository.Abandon(ctx, a, r.ID)
		if err != nil {
			t.Fatal(err)
		}
		if r.ID == acceptedID && ref != nil {
			t.Fatal("accepted original became reapable")
		}
		if r.ID != acceptedID {
			if ref == nil {
				t.Fatal("duplicate loser not reapable")
			}
			if err = f.repository.Reaped(ctx, *ref, m.DocumentStagedUploadRetention()); err != nil {
				t.Fatal(err)
			}
		}
	}
	other := f.addActor(t)
	otherDoc := f.accept(t, other, hash, "Same bytes other library")
	if otherDoc.ID == doc.ID {
		t.Fatal("shared physical document")
	}
	if _, err = f.repository.Reference(ctx, other, doc.ID); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("foreign content reference: %v", err)
	}
	paused := f.stage(t, a, strings.Repeat("b", 64))
	f.exec(t, "DELETE FROM sessions WHERE digest=$1", a.SessionDigest)
	if _, err = f.acceptReservation(ctx, a, paused.ID, metadata, time.Now()); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("revoked authority committed: %v", err)
	}
	ref, err := f.repository.Abandon(ctx, a, paused.ID)
	if err != nil || ref == nil {
		t.Fatalf("revoked request cleanup: %v", err)
	}
	expired := f.stage(t, other, strings.Repeat("c", 64))
	f.exec(t, "UPDATE document_uploads SET expires_at=clock_timestamp()-interval '1 second' WHERE id=$1", expired.ID)
	refs, err := f.repository.Reap(ctx, m.DocumentStagedUploadRetention())
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, ref := range refs {
		if ref.DocumentID == expired.ID {
			found = true
		}
	}
	if !found {
		t.Fatal("expired reservation omitted")
	}
	if _, err = f.acceptReservation(ctx, other, expired.ID, metadata, time.Now()); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("reaping reservation accepted: %v", err)
	}
}

func TestIngestionGenerationOutboxLeaseAndDeadlineFences(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	doc := f.accept(t, f.actor, strings.Repeat("d", 64), "Generations")
	j := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
	leases, err := f.service.Claim(ctx, 4, 30*time.Second)
	if err != nil || len(leases) != 1 {
		t.Fatalf("lease: %+v %v", leases, err)
	}
	if second, err := f.service.Claim(ctx, 4, 30*time.Second); err != nil || len(second) != 0 {
		t.Fatalf("duplicate lease: %+v %v", second, err)
	}
	lease := leases[0]
	bad := lease
	bad.LeaseToken = uuid.NewString()
	if err = f.repository.Acknowledge(ctx, bad, "document-ingestion-v1/"+j.AccountID+"/"+j.DocumentID+"/1", uuid.NewString()); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("foreign lease accepted: %v", err)
	}
	workflow := "document-ingestion-v1/" + j.AccountID + "/" + j.DocumentID + "/1"
	run := uuid.NewString()
	if err = f.repository.Acknowledge(ctx, lease, workflow, run); err != nil {
		t.Fatal(err)
	}
	pending, err := f.repository.Pending(ctx, 1)
	if err != nil || len(pending) != 1 || pending[0].RunID != run || pending[0].ProcessingDeadline == nil {
		t.Fatalf("ack not durable: %+v %v", pending, err)
	}
	deadline := *pending[0].ProcessingDeadline
	if pending, err = f.repository.Pending(ctx, 1); err != nil || len(pending) != 0 {
		t.Fatalf("unfair repeated reconciliation: %+v %v", pending, err)
	}
	if err = f.repository.FailExpired(ctx, j, "processing_timeout"); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("early expiration: %v", err)
	}
	f.admit(t, j)
	work, err := f.service.Work(ctx, j, "extracting")
	if err != nil {
		t.Fatal(err)
	}
	var after time.Time
	if err = f.connection.QueryRow(ctx, "SELECT processing_deadline FROM document_processing WHERE document_id=$1", doc.ID).Scan(&after); err != nil || !after.Equal(deadline) {
		t.Fatalf("activity extended deadline: %v %v", after, err)
	}
	if err = f.service.SaveExtraction(ctx, j, 0, "old extracted text"); err != nil {
		t.Fatal(err)
	}
	if err = f.repository.Fail(ctx, j, "processing_failed"); err != nil {
		t.Fatal(err)
	}
	if err = f.service.SaveEmbeddings(ctx, j, 1, m.DefaultConfiguration().EmbeddingSpace(), []m.DocumentChunk{{Text: "late", Vector: unitVector(0)}}); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("failed generation accepted writes: %v", err)
	}
	c, err := f.service.SetProcessingConfiguration(ctx, f.actor, m.DocumentProcessingConfiguration{Language: "eng", Segmentation: "single_block"})
	if err != nil {
		t.Fatal(err)
	}
	retried, err := f.service.Retry(ctx, f.actor, doc.ID)
	if err != nil || retried.Generation != 2 || retried.ConfigurationRevision != c.Revision {
		t.Fatalf("retry snapshot: %+v %v", retried, err)
	}
	if work.Configuration.Language != "eng+deu" {
		t.Fatal("old configuration mutated")
	}
	if err = f.repository.Fail(ctx, j, "processing_failed"); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("old generation failed new: %v", err)
	}
	j.Generation = 2
	f.exec(t, "UPDATE document_processing SET delivery_deadline=clock_timestamp()-interval '1 second' WHERE document_id=$1", doc.ID)
	if err = f.repository.FailExpired(ctx, j, "delivery_timeout"); err != nil {
		t.Fatal(err)
	}
	if _, err = f.service.Work(ctx, j, "extracting"); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("expired generation read: %v", err)
	}
	if _, err = f.repository.Reference(ctx, f.actor, doc.ID); err != nil {
		t.Fatalf("failed original inaccessible: %v", err)
	}
}

func TestSearchUsesCurrentLexicalTextAndOnlyCompleteSemanticGeneration(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	doc := f.accept(t, f.actor, strings.Repeat("e", 64), "Oldmetadataterm")
	search := func(query, mode string, vector []float64) m.DocumentSearchResults {
		t.Helper()
		input, _ := (m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Query: query, Mode: mode, Limit: 20}).Normalize()
		result, err := f.search(ctx, f.actor, input, vector)
		if err != nil {
			t.Fatal(err)
		}
		return result
	}
	if *search("Oldmetadataterm", "fulltext", nil).Total != 1 {
		t.Fatal("queued metadata missing")
	}
	j := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
	f.admit(t, j)
	work, err := f.service.Work(ctx, j, "extracting")
	if err != nil {
		t.Fatal(err)
	}
	if err = f.service.SaveExtraction(ctx, j, 0, "private extracted solar panel"); err != nil {
		t.Fatal(err)
	}
	if *search("solar", "fulltext", nil).Total != 1 {
		t.Fatal("effective extracted text must be lexically searchable before indexing completes")
	}
	updated := "Newmetadataterm"
	if _, err = f.service.Update(ctx, f.actor, doc.ID, m.DocumentMetadataPatch{Title: &updated}); err != nil {
		t.Fatal(err)
	}
	if err = f.service.SaveEmbeddings(ctx, j, 1, m.DefaultConfiguration().EmbeddingSpace(), []m.DocumentChunk{{Text: "private extracted solar panel", Vector: unitVector(0)}}); err != nil {
		t.Fatal(err)
	}
	work.Reference.Location = "final"
	if err = f.service.Publish(ctx, j, 1); err != nil {
		t.Fatal(err)
	}
	finalizer := services.NewDocumentIngestionService(f.repository, nil, nil, f.authority, time.Now)
	for range 2 {
		if err = finalizer.Finalize(ctx, j); err != nil {
			t.Fatalf("replayed committed finalization: %v", err)
		}
	}
	superseded := j
	superseded.Generation++
	if err = finalizer.Finalize(ctx, superseded); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("different generation finalization: %v", err)
	}
	retired, err := f.repository.Reap(ctx, m.DocumentStagedUploadRetention())
	if err != nil || len(retired) != 1 || retired[0].DocumentID != doc.ID || retired[0].Location != "staged" {
		t.Fatalf("post-publication staging recovery: %+v %v", retired, err)
	}
	if err = f.repository.Reaped(ctx, retired[0], m.DocumentStagedUploadRetention()); err != nil {
		t.Fatal(err)
	}
	if reference, err := f.repository.Reference(ctx, f.actor, doc.ID); err != nil || reference.Location != "final" {
		t.Fatalf("staging retirement removed final reference: %+v %v", reference, err)
	}
	if *search("Oldmetadataterm", "fulltext", nil).Total != 0 || *search("Newmetadataterm", "fulltext", nil).Total != 1 || *search("solar", "fulltext", nil).Total != 1 {
		t.Fatal("current metadata or ready text search incorrect")
	}
	found, err := f.documents.Get(ctx, f.actor.AccountID, doc.ID)
	if err != nil || found.Title != updated || found.Processing.State != "ready" {
		t.Fatalf("processing overwrote metadata: %+v %v", found, err)
	}
	other := f.accept(t, f.actor, strings.Repeat("f", 64), "Other")
	f.ready(t, other, "Wind turbine", unitVector(1))
	results := search("semantic query", "semantic", unitVector(0))
	if results.Total != nil || len(results.Items) != 2 || results.Items[0].Document.ID != doc.ID || math.Abs(results.Items[0].Score-1) > 1e-9 || math.Abs(results.Items[1].Score) > 1e-9 {
		t.Fatalf("not real cosine ranking: %+v", results)
	}
	input, _ := (m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Query: "semantic", Mode: "semantic", Limit: 1, Offset: 1}).Normalize()
	page, err := f.search(ctx, f.actor, input, unitVector(0))
	if err != nil || page.Total != nil || len(page.Items) != 1 || page.Items[0].Document.ID != other.ID {
		t.Fatalf("semantic pagination: %+v %v", page, err)
	}
	f.exec(t, "UPDATE memberships SET is_owner=false,role='viewer',claims='{}' WHERE account_id=$1 AND user_id=$2", f.actor.AccountID, f.actor.UserID)
	f.exec(t, "DELETE FROM sessions WHERE digest=$1", f.actor.SessionDigest)
	if _, err = f.search(ctx, f.actor, input, unitVector(0)); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("search released revoked authority: %v", err)
	}
}

func TestSemanticSearchBeyondFormerCapacityAndFairPending(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	vector := unitVector(0)
	for i := range 17 {
		doc := f.accept(t, f.actor, fmt.Sprintf("%064x", i+1), fmt.Sprintf("Corpus %d", i))
		f.ready(t, doc, "Document content", vector)
		if i < 16 {
			f.exec(t, `INSERT INTO document_chunks(account_id,document_id,generation,position,content,embedding,model_digest) SELECT $1,$2,1,g,'additional content',$3,$4 FROM generate_series(1,255) g`, f.actor.AccountID, doc.ID, vector, m.EmbeddingDigest)
		}
		if i == 15 {
			input, _ := (m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Query: "query", Mode: "semantic"}).Normalize()
			start := time.Now()
			result, err := f.search(ctx, f.actor, input, vector)
			elapsed := time.Since(start)
			t.Logf("semantic complete 4096-chunk query: %s", elapsed)
			if err != nil || result.Total != nil || len(result.Items) != 16 {
				t.Fatalf("search boundary: %+v %v", result, err)
			}
			if elapsed > 5*time.Second {
				t.Fatalf("bounded search exceeded timeout: %s", elapsed)
			}
		}
	}
	input, _ := (m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Query: "query", Mode: "semantic"}).Normalize()
	if result, err := f.search(ctx, f.actor, input, vector); err != nil || result.Total != nil || len(result.Items) != 17 {
		t.Fatalf("corpus beyond former limit: %+v %v", result, err)
	}
	f.exec(t, `UPDATE documents SET sender='Capacity%_sender',bcc=ARRAY['Capacity%_recipient'],tags=ARRAY['capacity'] WHERE title='Corpus 16'`)
	filtered := input
	filtered.Sender, filtered.Recipient, filtered.Tags = "%_sender", "%_recipient", []string{"capacity"}
	result, err := f.search(ctx, f.actor, filtered, vector)
	if err != nil || result.Total != nil || len(result.Items) != 1 || result.Items[0].Document.Title != "Corpus 16" {
		t.Fatalf("filters did not narrow eligible semantic results: %+v %v", result, err)
	}
	f.exec(t, `UPDATE documents SET sender='prefixCapacity%_sender',cc=ARRAY['prefixCapacity%_recipient'] WHERE title<>'Corpus 16'`)
	for _, modes := range [][2]string{{"exact", "contains"}, {"contains", "exact"}, {"exact", "exact"}, {"contains", "contains"}} {
		selected := input
		selected.Sender, selected.Recipient = "Capacity%_sender", "Capacity%_recipient"
		selected.SenderMatch, selected.RecipientMatch = modes[0], modes[1]
		result, err := f.search(ctx, f.actor, selected, vector)
		if modes == [2]string{"contains", "contains"} {
			if err != nil || len(result.Items) != 17 || result.Total != nil {
				t.Fatalf("contains modes lost eligible documents: %+v %v", result, err)
			}
		} else if err != nil || result.Total != nil || len(result.Items) != 1 || result.Items[0].Document.Title != "Corpus 16" {
			t.Fatalf("independent exact modes %v did not narrow eligible rows: %+v %v", modes, result, err)
		}
	}
	for i := range 25 {
		f.accept(t, f.actor, fmt.Sprintf("%064x", 100+i), "Pending fairness")
	}
	pending, err := f.repository.Pending(ctx, 20)
	if err != nil || len(pending) != 0 {
		t.Fatalf("unadmitted work acquired execution reconciliation: %d %v", len(pending), err)
	}
	leases, err := f.service.Claim(ctx, 20, 30*time.Second, "repository-test")
	if err != nil || len(leases) != 1 {
		t.Fatalf("shared admission exceeded one execution: %d %v", len(leases), err)
	}
	var waiting int
	if err = f.connection.QueryRow(ctx, "SELECT count(*) FROM document_processing WHERE state='queued' AND delivery_deadline IS NULL").Scan(&waiting); err != nil || waiting != 24 {
		t.Fatalf("waiting admission deadlines: %d %v", waiting, err)
	}

}

func TestOCRCorrectionTransitionsAndDurableDeletion(t *testing.T) {
	for _, final := range []bool{false, true} {
		for _, empty := range []bool{false, true} {
			t.Run(fmt.Sprintf("final=%v/empty=%v", final, empty), func(t *testing.T) {
				f := newIngestionFixture(t)
				ctx := t.Context()
				doc := f.accept(t, f.actor, strings.Repeat("9", 64), "OCR transitions")
				if final {
					f.ready(t, doc, "old original text", unitVector(0))
				}
				before, err := f.service.OCR(ctx, f.actor, doc.ID)
				if err != nil {
					t.Fatal(err)
				}
				text := " correctedneedle\r\n世界 \t"
				if empty {
					text = " \r\n\t\x01 "
				}
				corrected, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: before.Revision, Text: text})
				if err != nil {
					t.Fatal(err)
				}
				if corrected.Status != "available" || corrected.Revision != before.Revision+1 || corrected.Text == nil || *corrected.Text != text || corrected.Origin == nil || *corrected.Origin != "manual" {
					t.Fatalf("lost exact correction: %+v", corrected)
				}
				if _, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: before.Revision, Text: "stale"}); !errors.Is(err, m.ErrConflict) {
					t.Fatalf("stale revision accepted: %v", err)
				}
				processing, err := f.service.Processing(ctx, f.actor, doc.ID)
				if err != nil {
					t.Fatal(err)
				}
				expectedStage, expectedState := "embedding", "queued"
				if empty {
					expectedStage = "finalizing"
					if final {
						expectedState = "ready"
						expectedStage = "complete"
					}
				}
				if processing.Stage != expectedStage || processing.State != expectedState {
					t.Fatalf("wrong transition: %+v", processing)
				}
				var outboxCount int
				if err := f.connection.QueryRow(ctx, "SELECT count(*) FROM document_outbox WHERE document_id=$1", doc.ID).Scan(&outboxCount); err != nil {
					t.Fatal(err)
				}
				expectedJobs := 1
				if final && empty {
					expectedJobs = 0
				}
				if outboxCount != expectedJobs {
					t.Fatalf("outbox=%d want%d", outboxCount, expectedJobs)
				}
				lexical, _ := (m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Query: "correctedneedle", Mode: "fulltext"}).Normalize()
				hits, err := f.search(ctx, f.actor, lexical, nil)
				expectedHits := int64(1)
				if empty {
					expectedHits = 0
				}
				if err != nil || hits.Total == nil || *hits.Total != expectedHits {
					t.Fatalf("current lexical text missing: %+v %v", hits, err)
				}
				semantic, _ := (m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Query: "needle", Mode: "semantic"}).Normalize()
				hits, err = f.search(ctx, f.actor, semantic, unitVector(0))
				if err != nil || hits.Total != nil || len(hits.Items) != 0 {
					t.Fatalf("stale semantic vectors retained: %+v %v", hits, err)
				}
				j := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: processing.Generation}
				if expectedJobs != 0 {
					f.admit(t, j)
					work, err := f.service.Work(ctx, j, "extracting")
					if err != nil || work.Revision != corrected.Revision || work.Stage != expectedStage {
						t.Fatalf("wrong generation binding: %+v %v", work, err)
					}
					if !empty {
						for i := range work.Chunks {
							work.Chunks[i].Vector = unitVector(0)
						}
						if err := f.service.SaveEmbeddings(ctx, j, work.Revision, m.DefaultConfiguration().EmbeddingSpace(), work.Chunks); err != nil {
							t.Fatal(err)
						}
					}
					if err := f.service.Publish(ctx, j, corrected.Revision); err != nil {
						t.Fatal(err)
					}
				}
				reloaded, err := f.service.OCR(ctx, f.actor, doc.ID)
				expectedIndexing := "ready"
				if empty {
					expectedIndexing = "not_required"
				}
				if err != nil || reloaded.Text == nil || *reloaded.Text != text || reloaded.SemanticIndexing != expectedIndexing {
					t.Fatalf("correction changed after publication: %+v %v", reloaded, err)
				}
				if err := f.service.Delete(ctx, f.actor, doc.ID); err != nil {
					t.Fatal(err)
				}
				if _, err := f.service.OCR(ctx, f.actor, doc.ID); !errors.Is(err, m.ErrNotFound) {
					t.Fatalf("deleted text still available: %v", err)
				}
				if _, err := f.service.Work(ctx, j, "finalizing"); !errors.Is(err, m.ErrStaleJob) {
					t.Fatalf("deleted generation accepted: %v", err)
				}
				leases, err := f.repository.ReapDeleted(ctx, 20)
				if err != nil || len(leases) != 1 || leases[0].DocumentID != doc.ID {
					t.Fatalf("missing durable cleanup: %+v %v", leases, err)
				}
				if err := f.repository.DeletedReaped(ctx, leases[0], m.PlanDocumentCleanup(leases[0], true, time.Now())); err != nil {
					t.Fatal(err)
				}
				f.exec(t, "UPDATE document_cleanup SET next_attempt_at=clock_timestamp()-interval '1 second' WHERE document_id=$1", doc.ID)
				again, err := f.repository.ReapDeleted(ctx, 20)
				if err != nil || len(again) != 1 || again[0].LeaseToken == leases[0].LeaseToken {
					t.Fatalf("successful cleanup discarded durable identity: %+v %v", again, err)
				}
			})
		}
	}
}

func TestOCRCorrectionSurvivesMachineRetryAndLegacyRecovery(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	doc := f.accept(t, f.actor, strings.Repeat("8", 64), "Correction during extraction")
	initial := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
	f.admit(t, initial)
	if _, err := f.service.Work(ctx, initial, "extracting"); err != nil {
		t.Fatal(err)
	}
	corrected, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: 0, Text: "Durable manualneedle\r\n"})
	if err != nil {
		t.Fatal(err)
	}
	if err := f.service.SaveExtraction(ctx, initial, 0, "obsolete machine"); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("late extraction replaced manual correction: %v", err)
	}
	current := initial
	current.Generation = 2
	if err := f.repository.Fail(ctx, current, "inference_unavailable"); err != nil {
		t.Fatal(err)
	}
	retried, err := f.service.Retry(ctx, f.actor, doc.ID)
	if err != nil {
		t.Fatal(err)
	}
	current.Generation = retried.Generation
	query, _ := (m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: "fulltext", Query: "manualneedle"}).Normalize()
	found, err := f.search(ctx, f.actor, query, nil)
	if err != nil || found.Total == nil || *found.Total != 1 {
		t.Fatalf("retry hid effective correction: %+v %v", found, err)
	}
	f.admit(t, current)
	work, err := f.service.Work(ctx, current, "extracting")
	if err != nil || work.Revision != corrected.Revision {
		t.Fatalf("retry binding: %+v %v", work, err)
	}
	if err := f.service.SaveExtraction(ctx, current, work.Revision, "new machine OCR"); err != nil {
		t.Fatal(err)
	}
	result, err := f.service.OCR(ctx, f.actor, doc.ID)
	if err != nil || result.Revision != corrected.Revision || result.Text == nil || *result.Text != *corrected.Text {
		t.Fatalf("machine retry changed correction: %+v %v", result, err)
	}
	var machine string
	if err := f.connection.QueryRow(ctx, "SELECT ocr_machine_text FROM documents WHERE id=$1", doc.ID).Scan(&machine); err != nil || machine != "new machine OCR" {
		t.Fatalf("machine source was not retained separately: %q %v", machine, err)
	}

	next, err := f.service.Work(ctx, current, "embedding")
	if err != nil {
		t.Fatal(err)
	}
	for i := range next.Chunks {
		next.Chunks[i].Vector = unitVector(0)
	}
	if err = f.service.SaveEmbeddings(ctx, current, next.Revision, next.Configuration.EmbeddingSpace(), next.Chunks); err != nil {
		t.Fatal(err)
	}
	if err = f.service.Publish(ctx, current, next.Revision); err != nil {
		t.Fatal(err)
	}
	f.closeTerminal(t)
	legacy := f.accept(t, f.actor, strings.Repeat("7", 64), "Legacy extraction")
	f.ready(t, legacy, "legacy text", unitVector(0))
	if _, err := f.service.Retry(ctx, f.actor, legacy.ID); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("ordinary ready document can retry: %v", err)
	}
	f.exec(t, "UPDATE documents SET ocr_machine_text=NULL WHERE id=$1", legacy.ID)
	missing, err := f.service.OCR(ctx, f.actor, legacy.ID)
	if err != nil || missing.Text != nil || missing.Reason == nil || *missing.Reason != "legacy_text_missing" {
		t.Fatalf("legacy chunks advertised as canonical text: %+v %v", missing, err)
	}
	recovered, err := f.service.Retry(ctx, f.actor, legacy.ID)
	if err != nil || recovered.State != "queued" || recovered.Generation != 2 {
		t.Fatalf("legacy recovery refused: %+v %v", recovered, err)
	}
	j := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: legacy.ID, Generation: recovered.Generation}
	f.admit(t, j)
	work, err = f.service.Work(ctx, j, "extracting")
	if err != nil {
		t.Fatal(err)
	}
	if err := f.service.SaveExtraction(ctx, j, work.Revision, " exact recovered\n"); err != nil {
		t.Fatal(err)
	}
	result, err = f.service.OCR(ctx, f.actor, legacy.ID)
	if err != nil || result.Text == nil || *result.Text != " exact recovered\n" || result.Revision != missing.Revision+1 {
		t.Fatalf("recovery did not install exact text: %+v %v", result, err)
	}
}

func (f *ingestionFixture) closeTerminal(t *testing.T) {
	t.Helper()
	pending, err := f.repository.Pending(t.Context(), 100)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range pending {
		var status string
		if err = f.connection.QueryRow(t.Context(), `SELECT status FROM document_processing_jobs WHERE account_id=$1 AND document_id=$2 AND generation=$3`, p.Job.AccountID, p.Job.DocumentID, p.Job.Generation).Scan(&status); err != nil {
			t.Fatal(err)
		}
		code := ""
		if status != "queued" && status != "running" {
			code = "processing_incomplete"
		}
		if err = f.service.ResolveExecution(t.Context(), p, p.RunID, code, false); err != nil {
			t.Fatal(err)
		}
	}
}
func (f *ingestionFixture) admit(t *testing.T, j m.DocumentJob) {
	t.Helper()
	f.closeTerminal(t)
	var admitted bool
	if err := f.connection.QueryRow(t.Context(), `SELECT delivery_deadline IS NOT NULL FROM document_processing WHERE account_id=$1 AND document_id=$2 AND generation=$3`, j.AccountID, j.DocumentID, j.Generation).Scan(&admitted); err != nil {
		t.Fatal(err)
	}
	if admitted {
		return
	}
	leases, err := f.service.Claim(t.Context(), 1, 30*time.Second, "repository-test")
	if err != nil || len(leases) != 1 || leases[0].Job != j {
		t.Fatalf("admit fixture generation %v: %v %v", j, leases, err)
	}
	if err = f.repository.Acknowledge(t.Context(), leases[0], leases[0].WorkflowID, uuid.NewString()); err != nil {
		t.Fatal(err)
	}
}

func (f *ingestionFixture) resourceCapacity(t *testing.T, capacity int) {
	t.Helper()
	actor := schedulermodels.SchedulerActor{AccountID: f.actor.AccountID, UserID: f.actor.UserID, SessionDigest: f.actor.SessionDigest, CredentialRevision: f.actor.CredentialRevision}
	service := schedulerservices.NewSchedulerService(schedulerrepos.NewSchedulerRepository(f.scheduler), f.authority)
	settings, err := service.Settings(t.Context(), actor)
	if err != nil {
		t.Fatal(err)
	}
	_, err = service.UpdateSettings(t.Context(), actor, schedulermodels.SchedulerSettingsUpdate{ExpectedRevision: settings.Revision, Resources: []schedulermodels.SchedulerResourceUpdate{{ID: "worker", Limit: capacity}, {ID: "ollama", Limit: capacity}}})
	if err != nil {
		t.Fatal(err)
	}
}

type documentFixtureProcessor struct {
	documentinterfaces.DocumentProcessor
	vector []float64
}

func (p documentFixtureProcessor) Ready(context.Context) error { return nil }
func (p documentFixtureProcessor) Embed(_ context.Context, space m.DocumentEmbeddingSpace, _ string, _ []string) (m.DocumentEmbedding, error) {
	return m.DocumentEmbedding{Space: space, Model: space.Model, Digest: space.Digest, Vectors: [][]float64{p.vector}}, nil
}
func (f *ingestionFixture) search(ctx context.Context, a m.DocumentActor, input m.DocumentSearchInput, vector []float64) (m.DocumentSearchResults, error) {
	service := services.NewDocumentIngestionService(f.repository, nil, documentFixtureProcessor{vector: vector}, f.authority, time.Now)
	return service.Search(ctx, a, input)
}

func (f *ingestionFixture) setRepository(repository *repos.DocumentIngestionRepository) {
	f.repository = repository
	f.service = services.NewDocumentIngestionService(repository, nil, documentFixtureProcessor{}, f.authority, time.Now)
}

func (f *ingestionFixture) acceptReservation(ctx context.Context, actor m.DocumentActor, id string, metadata m.DocumentMetadata, _ time.Time) (m.Document, error) {
	return f.service.AcceptUpload(ctx, actor, m.DocumentUploadReservation{ExpiresAt: time.Now().Add(5 * time.Minute), ID: id}, metadata)
}

func initializeDocumentSource(ctx context.Context, source *sources.DocumentDataSource) error {
	return services.NewDocumentInitializationService(repos.NewDocumentInitializationRepository(source)).Initialize(ctx)
}
