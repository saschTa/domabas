//go:build integration

package repos_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	documentsources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	documentrepos "github.com/domabas/domabas/backend/internal/data/document/repos"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	documentmodels "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestPostgresRepositoryAndConcurrentMigrations(t *testing.T) {
	databaseURL := testdb.New(t)
	source, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(source.Close)
	var workers sync.WaitGroup
	for range 3 {
		workers.Go(func() {
			if err := source.Migrate(t.Context()); err != nil {
				t.Errorf("concurrent migration: %v", err)
			}
		})
	}
	workers.Wait()
	if t.Failed() {
		t.FailNow()
	}
	accountID := fixtureAccount(t, databaseURL)
	repository := documentrepos.NewDocumentRepository(documentsources.NewDocumentDataSource(source.Database()))
	empty, err := repository.List(t.Context(), accountID, documentmodels.DocumentPageRequest{Limit: 50})
	if err != nil {
		t.Fatal(err)
	}
	if empty.Items == nil || len(empty.Items) != 0 || empty.Total != 0 {
		t.Fatalf("invalid empty list: %+v", empty)
	}
	stamp := time.Date(2026, 9, 17, 12, 0, 0, 0, time.UTC)
	for _, id := range []string{"00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"} {
		doc := documentmodels.Document{ID: id, Title: "税務書類", Description: "Description", CreatedAt: stamp}
		if _, err := repository.Create(t.Context(), accountID, doc); err != nil {
			t.Fatal(err)
		}
	}
	page, err := repository.List(t.Context(), accountID, documentmodels.DocumentPageRequest{Limit: 1})
	if err != nil {
		t.Fatal(err)
	}
	if page.Total != 2 || len(page.Items) != 1 || page.Items[0].ID != "00000000-0000-4000-8000-000000000002" {
		t.Fatalf("unstable ordering/count: %+v", page)
	}
	page, err = repository.List(t.Context(), accountID, documentmodels.DocumentPageRequest{Limit: 1, Offset: 1})
	if err != nil {
		t.Fatal(err)
	}
	if page.Total != 2 || page.Items[0].ID != "00000000-0000-4000-8000-000000000001" {
		t.Fatalf("invalid offset: %+v", page)
	}
	found, err := repository.Get(t.Context(), accountID, page.Items[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	if found.Title != "税務書類" || !found.CreatedAt.Equal(stamp) {
		t.Fatalf("roundtrip changed data: %+v", found)
	}
	if _, err := repository.Get(t.Context(), accountID, "00000000-0000-4000-8000-000000000003"); !errors.Is(err, documentmodels.ErrNotFound) {
		t.Fatalf("missing ID error: %v", err)
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := repository.List(ctx, accountID, documentmodels.DocumentPageRequest{Limit: 50}); err == nil {
		t.Fatal("cancelled context ignored")
	}
	second, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(second.Close)
	if _, err := documentrepos.NewDocumentRepository(documentsources.NewDocumentDataSource(second.Database())).Get(t.Context(), accountID, found.ID); err != nil {
		t.Fatal(err)
	}
}

func TestPostgresRepositorySchemaIsolationAndUUIDMapping(t *testing.T) {
	repositories := make([]*documentrepos.DocumentRepository, 0, 2)
	accounts := make([]string, 0, 2)
	stamp := time.Date(2026, 9, 17, 12, 30, 0, 123000000, time.FixedZone("input", 7200))
	id := "ABCDEFAB-0000-4000-8000-000000000001"
	for _, title := range []string{"first schema", "second schema"} {
		databaseURL := testdb.New(t)
		source, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(source.Close)
		if err := source.Migrate(t.Context()); err != nil {
			t.Fatal(err)
		}
		accountID := fixtureAccount(t, databaseURL)
		accounts = append(accounts, accountID)
		repository := documentrepos.NewDocumentRepository(documentsources.NewDocumentDataSource(source.Database()))
		repositories = append(repositories, repository)
		created, err := repository.Create(t.Context(), accountID, documentmodels.Document{ID: id, Title: title, CreatedAt: stamp})
		if err != nil {
			t.Fatal(err)
		}
		if created.ID != "abcdefab-0000-4000-8000-000000000001" || created.CreatedAt.Location() != time.UTC || !created.CreatedAt.Equal(stamp) {
			t.Fatalf("UUID or UTC mapping changed: %+v", created)
		}
	}
	for index, repository := range repositories {
		accountID := accounts[index]
		found, err := repository.Get(t.Context(), accountID, id)
		if err != nil {
			t.Fatal(err)
		}
		if found.Title != []string{"first schema", "second schema"}[index] {
			t.Fatalf("read another schema: %+v", found)
		}
		page, err := repository.List(t.Context(), accountID, documentmodels.DocumentPageRequest{Limit: 10})
		if err != nil || page.Total != 1 || len(page.Items) != 1 || page.Items[0].Title != found.Title {
			t.Fatalf("list crossed schemas: %+v %v", page, err)
		}
		if _, err := repository.Get(t.Context(), accountID, "invalid UUID"); err == nil {
			t.Fatal("accepted invalid get UUID")
		}
		if _, err := repository.Create(t.Context(), accountID, documentmodels.Document{ID: "invalid UUID", Title: "invalid", CreatedAt: stamp}); err == nil {
			t.Fatal("accepted invalid create UUID")
		}
	}
}

func fixtureAccount(t *testing.T, databaseURL string) string {
	t.Helper()
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(t.Context())
	id := uuid.NewString()
	if _, err := connection.Exec(t.Context(), "INSERT INTO accounts(id,name) VALUES($1,'Test account')", id); err != nil {
		t.Fatal(err)
	}
	return id
}

func TestDocumentsAreIsolatedByAccountIncludingCountsAndLegacyRows(t *testing.T) {
	databaseURL := testdb.New(t)
	source, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	first, second := fixtureAccount(t, databaseURL), fixtureAccount(t, databaseURL)
	repo := documentrepos.NewDocumentRepository(documentsources.NewDocumentDataSource(source.Database()))
	doc := documentmodels.Document{ID: uuid.NewString(), Title: "Only first", CreatedAt: time.Now().UTC()}
	if _, err := repo.Create(t.Context(), first, doc); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(t.Context())
	if _, err := connection.Exec(t.Context(), "INSERT INTO documents(id,title,created_at) VALUES($1,'Unassigned legacy',now())", uuid.NewString()); err != nil {
		t.Fatal(err)
	}
	page, err := repo.List(t.Context(), first, documentmodels.DocumentPageRequest{Limit: 50})
	if err != nil || page.Total != 1 || len(page.Items) != 1 {
		t.Fatalf("first account count/items leaked: %+v %v", page, err)
	}
	empty, err := repo.List(t.Context(), second, documentmodels.DocumentPageRequest{Limit: 50})
	if err != nil || empty.Total != 0 || len(empty.Items) != 0 {
		t.Fatalf("second account count/items leaked: %+v %v", empty, err)
	}
	if _, err := repo.Get(t.Context(), second, doc.ID); !errors.Is(err, documentmodels.ErrNotFound) {
		t.Fatalf("foreign document accessible: %v", err)
	}
	for _, scope := range []string{"", "invalid"} {
		if _, err := repo.Get(t.Context(), scope, doc.ID); err == nil {
			t.Fatal("unscoped get accepted")
		}
		if _, err := repo.List(t.Context(), scope, documentmodels.DocumentPageRequest{Limit: 50}); err == nil {
			t.Fatal("unscoped list accepted")
		}
		if _, err := repo.Create(t.Context(), scope, doc); err == nil {
			t.Fatal("unscoped create accepted")
		}
	}
}
