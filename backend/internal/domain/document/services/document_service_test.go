package services_test

import (
	"context"
	"errors"
	"testing"
	"time"

	documentmodels "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentservices "github.com/domabas/domabas/backend/internal/domain/document/services"
)

const accountID = "e9d6f5eb-151a-4889-b70d-ad7ce0f98e03"

type repositoryStub struct {
	created []documentmodels.Document
	err     error
}

func (repo *repositoryStub) Create(_ context.Context, _ string, doc documentmodels.Document) (documentmodels.Document, error) {
	repo.created = append(repo.created, doc)
	return doc, repo.err
}
func (repo *repositoryStub) Get(context.Context, string, string) (documentmodels.Document, error) {
	return documentmodels.Document{}, repo.err
}
func (repo *repositoryStub) List(context.Context, string, documentmodels.DocumentPageRequest) (documentmodels.DocumentPage, error) {
	return documentmodels.DocumentPage{}, repo.err
}

func TestCreateNormalizesAndAssignsIdentity(t *testing.T) {
	repo := &repositoryStub{}
	now := time.Date(2026, 9, 17, 12, 0, 0, 0, time.FixedZone("CEST", 7200))
	service := documentservices.NewDocumentService(repo, func() time.Time { return now })
	first, err := service.Create(t.Context(), accountID, documentmodels.DocumentCreateInput{Title: "  Invoice  ", Description: "Original"})
	if err != nil {
		t.Fatal(err)
	}
	second, err := service.Create(t.Context(), accountID, documentmodels.DocumentCreateInput{Title: "Other"})
	if err != nil {
		t.Fatal(err)
	}
	if first.Title != "Invoice" || first.Description != "Original" || !first.CreatedAt.Equal(now) || first.CreatedAt.Location() != time.UTC {
		t.Fatalf("unexpected document: %+v", first)
	}
	if len(first.ID) != 36 || first.ID[14] != '4' || first.ID == second.ID {
		t.Fatalf("invalid identities %q %q", first.ID, second.ID)
	}
}

func TestInvalidInputDoesNotReachStorage(t *testing.T) {
	repo := &repositoryStub{}
	service := documentservices.NewDocumentService(repo, time.Now)
	_, err := service.Create(t.Context(), accountID, documentmodels.DocumentCreateInput{Title: " "})
	var validation documentmodels.DocumentValidationError
	if !errors.As(err, &validation) || len(repo.created) != 0 {
		t.Fatalf("invalid input was persisted: %v", err)
	}
	for _, page := range []documentmodels.DocumentPageRequest{{Limit: 0}, {Limit: 101}, {Limit: 50, Offset: -1}} {
		if _, err := service.List(t.Context(), accountID, page); !errors.As(err, &validation) {
			t.Fatalf("invalid page accepted: %+v", page)
		}
	}
}

func TestRepositoryErrorsArePreserved(t *testing.T) {
	failure := errors.New("storage unavailable")
	service := documentservices.NewDocumentService(&repositoryStub{err: failure}, time.Now)
	if _, err := service.Create(t.Context(), accountID, documentmodels.DocumentCreateInput{Title: "Invoice"}); !errors.Is(err, failure) {
		t.Fatalf("lost storage error: %v", err)
	}
	if _, err := service.Get(t.Context(), accountID, "id"); !errors.Is(err, failure) {
		t.Fatalf("lost get error: %v", err)
	}
}

func TestMissingAccountScopeIsRejected(t *testing.T) {
	repo := &repositoryStub{}
	service := documentservices.NewDocumentService(repo, time.Now)
	for _, scope := range []string{"", "invalid", "00000000-0000-0000-0000-000000000000"} {
		if _, err := service.Create(t.Context(), scope, documentmodels.DocumentCreateInput{Title: "Valid"}); err == nil {
			t.Fatal("unscoped create accepted")
		}
		if _, err := service.Get(t.Context(), scope, "id"); err == nil {
			t.Fatal("unscoped get accepted")
		}
		if _, err := service.List(t.Context(), scope, documentmodels.DocumentPageRequest{Limit: 50}); err == nil {
			t.Fatal("unscoped list accepted")
		}
	}
	if len(repo.created) != 0 {
		t.Fatal("invalid scope reached repository")
	}
}
