//go:build integration

package repos_test

import (
	"context"
	"strings"
	"testing"
	"time"

	sources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

func TestConcurrentEmailProvidersReuseOneDocumentAfterHashCollision(t *testing.T) {
	f := newIngestionFixture(t)
	source := sources.NewDocumentIngestionDataSource(f.source.Database(), fixturePublication{}, f.scheduler)
	type stagedImport struct {
		authority   m.DocumentImportAuthority
		reservation m.DocumentUploadReservation
	}
	stage := func() stagedImport {
		a := m.DocumentImportAuthority{CredentialRevision: 1, ProviderID: uuid.NewString(), OwnerID: f.actor.UserID, AccountID: f.actor.AccountID, RunID: uuid.NewString(), MessageID: uuid.NewString(), PartID: uuid.NewString(), AttemptToken: uuid.NewString(), WorkflowRunID: uuid.NewString(), ActivityID: "import", ProviderRevision: 1, SourceGeneration: 1, MailboxGeneration: 1, ActivityAttempt: 1}
		f.exec(t, `INSERT INTO email_providers(id,account_id,owner_id,label,host,port,mailbox,enabled,interval_minutes,max_age_days,page_size,consent_revision) VALUES($1,$2,$3,'Collision','imap.example.test',993,'INBOX',true,15,30,20,1)`, a.ProviderID, a.AccountID, a.OwnerID)
		f.exec(t, `INSERT INTO email_runs(id,provider_id,account_id,owner_id,provider_revision,source_generation,mailbox_generation,trigger,status,stage,page_index,activity_id,activity_attempt,attempt_token,attempt_deadline,workflow_run_id) VALUES($1,$2,$3,$4,1,1,1,'manual','running','importing',0,$5,1,$6,clock_timestamp()+interval '60 seconds',$7)`, a.RunID, a.ProviderID, a.AccountID, a.OwnerID, a.ActivityID, a.AttemptToken, a.WorkflowRunID)
		f.exec(t, `INSERT INTO email_mailboxes(provider_id,source_generation,mailbox_generation,uid_validity,max_age_days) VALUES($1,1,1,1,30)`, a.ProviderID)
		f.exec(t, `INSERT INTO email_messages(id,provider_id,account_id,owner_id,source_generation,mailbox_generation,uid,run_id,provider_revision,attempt_token) VALUES($1,$2,$3,$4,1,1,1,$5,1,$6)`, a.MessageID, a.ProviderID, a.AccountID, a.OwnerID, a.RunID, a.AttemptToken)
		f.exec(t, `INSERT INTO email_parts(id,message_id,account_id,path,attempt_token) VALUES($1,$2,$3,'0',$4)`, a.PartID, a.MessageID, a.AccountID, a.AttemptToken)
		reservation, err := source.ReserveImport(t.Context(), a, m.DocumentUploadReservation{ExpiresAt: time.Now().Add(5 * time.Minute), ID: uuid.NewString(), AccountID: a.AccountID, UploaderID: a.OwnerID})
		if err != nil {
			t.Fatal(err)
		}
		reference := m.DocumentFileReference{AccountID: a.AccountID, UploaderID: a.OwnerID, DocumentID: reservation.ID, Location: "staged", File: m.DocumentFile{OriginalFilename: "same.eml", MediaType: "message/rfc822", Size: 20, SHA256: strings.Repeat("a", 64)}}
		if err := source.StageImport(t.Context(), a, reservation, reference); err != nil {
			t.Fatal(err)
		}
		return stagedImport{a, reservation}
	}
	first, second := stage(), stage()
	f.exec(t, `CREATE FUNCTION email_import_collision_barrier() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN PERFORM pg_advisory_xact_lock(hashtextextended(current_schema()||':email-import-collision',0)); RETURN NEW; END $$`)
	f.exec(t, `CREATE TRIGGER email_import_collision_barrier BEFORE INSERT ON documents FOR EACH ROW EXECUTE FUNCTION email_import_collision_barrier()`)
	blocker, err := f.source.Database().Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	if _, err := blocker.Exec(t.Context(), `SELECT pg_advisory_xact_lock(hashtextextended(current_schema()||':email-import-collision',0))`); err != nil {
		t.Fatal(err)
	}
	var pid int
	if err := blocker.QueryRow(t.Context(), "SELECT pg_backend_pid()").Scan(&pid); err != nil {
		t.Fatal(err)
	}
	type outcome struct {
		result m.DocumentImportResult
		err    error
	}
	results := make(chan outcome, 2)
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	metadata, err := (m.DocumentMetadata{Title: "Same email", Kind: "email"}).Normalize()
	if err != nil {
		t.Fatal(err)
	}
	for _, input := range []stagedImport{first, second} {
		go func() {
			facts, err := source.ImportAcceptanceFacts(ctx, input.authority, input.reservation)
			if err != nil {
				results <- outcome{err: err}
				return
			}
			command, err := m.PlanDocumentImportAcceptance(facts, metadata)
			if err != nil {
				results <- outcome{err: err}
				return
			}
			result, err := source.AcceptImport(ctx, input.authority, input.reservation, command)
			results <- outcome{result, err}
		}()
	}
	ticker := time.NewTicker(5 * time.Millisecond)
	defer ticker.Stop()
	for {
		var waiting int
		if err := f.connection.QueryRow(ctx, `WITH RECURSIVE waiting(pid) AS (SELECT pid FROM pg_stat_activity WHERE $1=ANY(pg_blocking_pids(pid)) UNION SELECT a.pid FROM pg_stat_activity a JOIN waiting w ON w.pid=ANY(pg_blocking_pids(a.pid))) SELECT count(*) FROM waiting`, pid).Scan(&waiting); err != nil {
			t.Fatal(err)
		}
		if waiting == 2 {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal("both imports did not reach insert after their missing-document reads")
		case <-ticker.C:
		}
	}
	if err := blocker.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	a, b := <-results, <-results
	if a.err != nil || b.err != nil || a.result.DocumentID != b.result.DocumentID || a.result.Reused == b.result.Reused {
		t.Fatalf("concurrent identical email imports did not accept and reuse one document: %+v (%v), %+v (%v)", a.result, a.err, b.result, b.err)
	}
	var documents, files, processing, outbox, accepted, reused, acceptedUploads, reapingUploads, acceptedCount, reusedCount int
	err = f.connection.QueryRow(t.Context(), `SELECT
 (SELECT count(*) FROM documents),(SELECT count(*) FROM document_files),(SELECT count(*) FROM document_processing),(SELECT count(*) FROM document_outbox),
 (SELECT count(*) FROM email_parts WHERE state='accepted' AND document_id=$1),(SELECT count(*) FROM email_parts WHERE state='reused' AND document_id=$1),
 (SELECT count(*) FROM document_uploads WHERE state='accepted'),(SELECT count(*) FROM document_uploads WHERE state='reaping'),
 (SELECT sum(messages_accepted) FROM email_runs),(SELECT sum(messages_reused) FROM email_runs)`, a.result.DocumentID).Scan(&documents, &files, &processing, &outbox, &accepted, &reused, &acceptedUploads, &reapingUploads, &acceptedCount, &reusedCount)
	if err != nil {
		t.Fatal(err)
	}
	if documents != 1 || files != 1 || processing != 1 || outbox != 1 || accepted != 1 || reused != 1 || acceptedUploads != 1 || reapingUploads != 1 || acceptedCount != 1 || reusedCount != 1 {
		t.Fatalf("collision left duplicate or incomplete state: docs=%d files=%d processing=%d outbox=%d parts=%d/%d uploads=%d/%d counters=%d/%d", documents, files, processing, outbox, accepted, reused, acceptedUploads, reapingUploads, acceptedCount, reusedCount)
	}
}
