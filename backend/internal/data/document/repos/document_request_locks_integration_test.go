//go:build integration

package repos_test

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	sources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	repos "github.com/domabas/domabas/backend/internal/data/document/repos"
	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/domain/document/services"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
)

func TestDocumentReadsDoNotWaitForIdentityTargetOrSchedulerLocks(t *testing.T) {
	f := newIngestionFixture(t)
	doc := f.accept(t, f.actor, strings.Repeat("a", 64), "Visible title")
	reservation := f.stage(t, f.actor, strings.Repeat("b", 64))
	f.exec(t, `UPDATE document_processing SET state='failed',failure_code='encrypted_pdf' WHERE document_id=$1`, doc.ID)
	jobs, err := f.service.Jobs(t.Context(), f.actor, m.DocumentProcessingPageInput{})
	if err != nil || len(jobs.Items) != 1 {
		t.Fatal(jobs, err)
	}
	configuration, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
	if err != nil {
		t.Fatal(err)
	}
	batch, err := f.service.CreateBatch(t.Context(), f.actor, false, m.DocumentReindexRequest{RequestID: uuid.NewString(), ConfigurationRevision: configuration.Revision})
	if err != nil {
		t.Fatal(err)
	}
	source := sources.NewDocumentDataSource(f.source.Database())
	blocker, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	for _, query := range []struct {
		sql string
		id  string
	}{
		{"SELECT id FROM accounts WHERE id=$1 FOR UPDATE", f.actor.AccountID},
		{"SELECT id FROM users WHERE id=$1 FOR UPDATE", f.actor.UserID},
		{"SELECT user_id FROM memberships WHERE user_id=$1 FOR UPDATE", f.actor.UserID},
		{"SELECT digest FROM sessions WHERE digest=$1 FOR UPDATE", f.actor.SessionDigest},
		{"SELECT id FROM documents WHERE id=$1 FOR UPDATE", doc.ID},
		{"SELECT document_id FROM document_processing WHERE document_id=$1 FOR UPDATE", doc.ID},
		{"SELECT id FROM document_uploads WHERE id=$1 FOR UPDATE", reservation.ID},
	} {
		if _, err := blocker.Exec(t.Context(), query.sql, query.id); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := blocker.Exec(t.Context(), `SELECT id FROM document_processing_configuration FOR UPDATE; SELECT pg_advisory_xact_lock(hashtextextended(current_database()||':'||current_schema()||':document-processing',0))`); err != nil {
		t.Fatal(err)
	}
	reads := map[string]func(context.Context) error{
		"jobs": func(ctx context.Context) error {
			_, err := f.service.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{Pipeline: "ingestion", Status: "failed"})
			return err
		},
		"job detail": func(ctx context.Context) error {
			_, err := f.service.JobHistory(ctx, f.actor, jobs.Items[0].ID)
			return err
		},
		"namespace configuration": func(ctx context.Context) error {
			_, err := f.service.NamespaceConfiguration(ctx, f.actor)
			return err
		},
		"system configuration": func(ctx context.Context) error {
			_, err := f.service.GetProcessingConfiguration(ctx, f.actor)
			return err
		},
		"search configuration": func(ctx context.Context) error { _, err := f.repository.SearchConfiguration(ctx, f.actor); return err },
		"batches": func(ctx context.Context) error {
			_, err := f.service.Batches(ctx, f.actor, false, m.DocumentProcessingPageInput{})
			return err
		},
		"batch detail": func(ctx context.Context) error {
			_, err := f.service.Batch(ctx, f.actor, false, batch.ID)
			return err
		},
		"processing": func(ctx context.Context) error { _, err := f.service.Processing(ctx, f.actor, doc.ID); return err },
		"original":   func(ctx context.Context) error { _, err := f.repository.Reference(ctx, f.actor, doc.ID); return err },
		"OCR":        func(ctx context.Context) error { _, err := f.service.OCR(ctx, f.actor, doc.ID); return err },
		"unlock preparation": func(ctx context.Context) error {
			_, err := f.service.UnlockReference(ctx, f.actor, doc.ID, 1)
			return err
		},
		"reservation": func(ctx context.Context) error {
			_, err := f.repository.Reservation(ctx, f.actor, reservation.ID)
			return err
		},
		"search": func(ctx context.Context) error {
			_, err := f.search(ctx, f.actor, m.DocumentSearchInput{Mode: "fulltext", Query: "Visible", Limit: 20, Sort: "relevance"}, nil)
			return err
		},
		"vocabulary": func(ctx context.Context) error {
			_, err := source.ListVocabularyRecords(ctx, f.actor, m.DocumentVocabularyInput{Field: "tag", Limit: 20})
			return err
		},
		"email parents": func(ctx context.Context) error {
			_, err := source.EmailParents(ctx, f.actor, doc.ID, 20, "")
			return err
		},
	}
	for name, read := range reads {
		t.Run(name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
			defer cancel()
			if err := read(ctx); err != nil {
				t.Fatalf("read waited for unrelated locks or failed: %v", err)
			}
		})
	}
}

func TestDocumentWritesDoNotLockAuthorityOrRewriteConfiguration(t *testing.T) {
	f := newIngestionFixture(t)
	reservation := f.stage(t, f.actor, strings.Repeat("c", 64))
	blocker, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	for _, query := range []struct{ sql, id string }{
		{"SELECT id FROM accounts WHERE id=$1 FOR NO KEY UPDATE", f.actor.AccountID},
		{"SELECT id FROM users WHERE id=$1 FOR NO KEY UPDATE", f.actor.UserID},
		{"SELECT user_id FROM memberships WHERE user_id=$1 FOR NO KEY UPDATE", f.actor.UserID},
		{"SELECT digest FROM sessions WHERE digest=$1 FOR NO KEY UPDATE", f.actor.SessionDigest},
	} {
		if _, err := blocker.Exec(t.Context(), query.sql, query.id); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := blocker.Exec(t.Context(), `SELECT id FROM document_processing_configuration FOR UPDATE; SELECT pg_advisory_xact_lock_shared(hashtextextended(current_database()||':'||current_schema()||':document-processing',0))`); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	metadata, err := (m.DocumentMetadata{Title: "Concurrent acceptance"}).Normalize()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.acceptReservation(ctx, f.actor, reservation.ID, metadata, time.Now().UTC()); err != nil {
		t.Fatalf("acceptance waited for authority, configuration or another ordinary publication: %v", err)
	}
	if _, err := f.documents.Create(ctx, f.actor.AccountID, m.Document{ID: uuid.NewString(), Title: "Concurrent metadata", CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("metadata creation waited for another ordinary publication: %v", err)
	}
}

type documentSnapshotPolicy struct {
	delegate p.DocumentAuthority
	entered  chan struct{}
	release  chan struct{}
	once     sync.Once
}

func (p *documentSnapshotPolicy) ResolveAuthority(ctx context.Context, actor identity.IdentityPrincipal) (identity.IdentityPrincipal, error) {
	principal, err := p.delegate.ResolveAuthority(ctx, actor)
	p.once.Do(func() { close(p.entered); <-p.release })
	return principal, err
}
func (p *documentSnapshotPolicy) ResolveBackgroundAuthority(ctx context.Context, account, user string, revision int64) (identity.IdentityPrincipal, error) {
	return p.delegate.ResolveBackgroundAuthority(ctx, account, user, revision)
}

func TestDocumentOperationAuthorityDoesNotBlockRevocation(t *testing.T) {
	f := newIngestionFixture(t)
	doc := f.accept(t, f.actor, strings.Repeat("d", 64), "Original title")
	barrier := &documentSnapshotPolicy{delegate: f.authority, entered: make(chan struct{}), release: make(chan struct{})}
	var release sync.Once
	defer release.Do(func() { close(barrier.release) })
	repository := services.NewDocumentIngestionService(repos.NewDocumentIngestionRepository(sources.NewDocumentDataSource(f.source.Database())), nil, nil, barrier, time.Now)
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	result := make(chan error, 1)
	go func() {
		page, err := repository.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{})
		if err == nil && (len(page.Items) != 1 || page.Items[0].DocumentTitle == nil || *page.Items[0].DocumentTitle != "Replacement title") {
			err = errors.New("authorized operation did not retain its permission or read current records")
		}
		result <- err
	}()
	select {
	case <-barrier.entered:
	case <-ctx.Done():
		t.Fatal("read never reached authority evaluation")
	}
	write, stop := context.WithTimeout(ctx, 2*time.Second)
	defer stop()
	if _, err := f.connection.Exec(write, "DELETE FROM sessions WHERE digest=$1", f.actor.SessionDigest); err != nil {
		t.Fatalf("read blocked revocation: %v", err)
	}
	if _, err := f.connection.Exec(write, "UPDATE documents SET title='Replacement title' WHERE id=$1", doc.ID); err != nil {
		t.Fatalf("read blocked document edit: %v", err)
	}
	release.Do(func() { close(barrier.release) })
	if err := <-result; err != nil {
		t.Fatal(err)
	}
	if _, err := repository.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{}); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("new read accepted revoked session: %v", err)
	}
}

func TestDocumentInitializedConfigurationIsNotRewritten(t *testing.T) {
	f := newIngestionFixture(t)
	before := ""
	if err := f.connection.QueryRow(t.Context(), "SELECT xmin::text FROM document_processing_configuration").Scan(&before); err != nil {
		t.Fatal(err)
	}
	source := sources.NewDocumentDataSource(f.source.Database())
	if err := initializeDocumentSource(t.Context(), source); err != nil {
		t.Fatal(err)
	}
	after := ""
	if err := f.connection.QueryRow(t.Context(), "SELECT xmin::text FROM document_processing_configuration").Scan(&after); err != nil || before != after {
		t.Fatalf("unchanged startup rewrote configuration: %s -> %s, %v", before, after, err)
	}
}
