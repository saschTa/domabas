package services

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type documentTestAuthority struct {
	principal identity.IdentityPrincipal
	err       error
	calls     int
}

func (a *documentTestAuthority) ResolveAuthority(context.Context, identity.IdentityPrincipal) (identity.IdentityPrincipal, error) {
	a.calls++
	return a.principal, a.err
}
func (a *documentTestAuthority) ResolveBackgroundAuthority(context.Context, string, string, int64) (identity.IdentityPrincipal, error) {
	a.calls++
	return a.principal, a.err
}
func documentAllowedAuthority() *documentTestAuthority {
	a := &documentTestAuthority{}
	for _, claim := range identity.ClaimCatalog() {
		a.principal.Permissions = append(a.principal.Permissions, claim.ID)
	}
	return a
}

func TestDocumentServiceEntryPointsRequireCurrentAuthority(t *testing.T) {
	operations := map[string]func(*DocumentIngestionService) error{
		"reserve": func(s *DocumentIngestionService) error {
			_, e := s.ReserveUpload(t.Context(), m.DocumentActor{})
			return e
		},
		"stage": func(s *DocumentIngestionService) error {
			_, e := s.StageUpload(t.Context(), m.DocumentActor{}, m.DocumentUploadReservation{}, "x.pdf", strings.NewReader("x"))
			return e
		},
		"accept": func(s *DocumentIngestionService) error {
			_, e := s.AcceptUpload(t.Context(), m.DocumentActor{}, m.DocumentUploadReservation{}, m.DocumentMetadata{})
			return e
		},
		"abandon": func(s *DocumentIngestionService) error {
			return s.AbandonUpload(t.Context(), m.DocumentActor{}, m.DocumentUploadReservation{})
		},
		"update": func(s *DocumentIngestionService) error {
			_, e := s.Update(t.Context(), m.DocumentActor{}, "", m.DocumentMetadataPatch{})
			return e
		},
		"content": func(s *DocumentIngestionService) error {
			_, e := s.OpenContent(t.Context(), m.DocumentActor{}, "")
			return e
		},
		"processing": func(s *DocumentIngestionService) error {
			_, e := s.Processing(t.Context(), m.DocumentActor{}, "")
			return e
		},
		"retry": func(s *DocumentIngestionService) error { _, e := s.Retry(t.Context(), m.DocumentActor{}, ""); return e },
		"search": func(s *DocumentIngestionService) error {
			_, e := s.Search(t.Context(), m.DocumentActor{}, m.DocumentSearchInput{})
			return e
		},
		"configuration": func(s *DocumentIngestionService) error {
			_, e := s.GetProcessingConfiguration(t.Context(), m.DocumentActor{})
			return e
		},
		"set configuration": func(s *DocumentIngestionService) error {
			_, e := s.SetProcessingConfiguration(t.Context(), m.DocumentActor{}, m.DocumentProcessingConfiguration{})
			return e
		},
		"model context": func(s *DocumentIngestionService) error {
			_, e := s.ModelContext(t.Context(), m.DocumentActor{}, "x")
			return e
		},
		"namespace configuration": func(s *DocumentIngestionService) error {
			_, e := s.NamespaceConfiguration(t.Context(), m.DocumentActor{})
			return e
		},
		"jobs": func(s *DocumentIngestionService) error {
			_, e := s.Jobs(t.Context(), m.DocumentActor{}, m.DocumentProcessingPageInput{})
			return e
		},
		"job": func(s *DocumentIngestionService) error {
			_, e := s.JobHistory(t.Context(), m.DocumentActor{}, "")
			return e
		},
		"batches": func(s *DocumentIngestionService) error {
			_, e := s.Batches(t.Context(), m.DocumentActor{}, true, m.DocumentProcessingPageInput{})
			return e
		},
		"batch": func(s *DocumentIngestionService) error {
			_, e := s.Batch(t.Context(), m.DocumentActor{}, false, "")
			return e
		},
		"create batch": func(s *DocumentIngestionService) error {
			_, e := s.CreateBatch(t.Context(), m.DocumentActor{}, true, m.DocumentReindexRequest{})
			return e
		},
		"retry AI": func(s *DocumentIngestionService) error {
			_, e := s.RetryAI(t.Context(), m.DocumentActor{}, "", m.DocumentReindexRequest{})
			return e
		},
		"OCR": func(s *DocumentIngestionService) error { _, e := s.OCR(t.Context(), m.DocumentActor{}, ""); return e },
		"correct OCR": func(s *DocumentIngestionService) error {
			_, e := s.CorrectOCR(t.Context(), m.DocumentActor{}, "", m.DocumentOCRCorrection{})
			return e
		},
		"delete": func(s *DocumentIngestionService) error { return s.Delete(t.Context(), m.DocumentActor{}, "") },
		"unlock": func(s *DocumentIngestionService) error {
			_, e := s.Unlock(t.Context(), m.DocumentActor{}, "", 1, "password")
			return e
		},
	}
	for name, operation := range operations {
		t.Run(name, func(t *testing.T) {
			authority := &documentTestAuthority{err: identity.ErrUnauthorized}
			service := NewDocumentIngestionService(nil, nil, nil, authority, time.Now)
			if err := operation(service); !errors.Is(err, m.ErrUnauthorized) || authority.calls != 1 {
				t.Fatalf("entry point bypassed current authority: %v (%d calls)", err, authority.calls)
			}
		})
	}
}

type documentStageRepository struct {
	p.DocumentIngestionRepository
	staged bool
}

func (r *documentStageRepository) Reservation(context.Context, m.DocumentActor, string) (m.DocumentUploadReservation, error) {
	return m.DocumentUploadReservation{ID: "document", AccountID: "account", UploaderID: "user", ExpiresAt: time.Now().Add(time.Minute)}, nil
}
func (r *documentStageRepository) RecordStaged(context.Context, m.DocumentActor, string, m.DocumentFileReference) error {
	r.staged = true
	return nil
}

type documentRevokingStore struct {
	p.DocumentContentStore
	authority *documentTestAuthority
}

func (s documentRevokingStore) Stage(context.Context, m.DocumentUploadReservation, string, io.Reader) (m.DocumentFileReference, error) {
	s.authority.err = identity.ErrUnauthorized
	return m.DocumentFileReference{AccountID: "account", UploaderID: "user", DocumentID: "document", Location: "staged"}, nil
}
func TestDocumentUploadReauthorizesAfterStreaming(t *testing.T) {
	authority := documentAllowedAuthority()
	repository := &documentStageRepository{}
	service := NewDocumentIngestionService(repository, documentRevokingStore{authority: authority}, nil, authority, time.Now)
	_, err := service.StageUpload(t.Context(), m.DocumentActor{}, m.DocumentUploadReservation{ID: "document"}, "x.pdf", strings.NewReader("x"))
	if !errors.Is(err, m.ErrUnauthorized) || repository.staged || authority.calls != 2 {
		t.Fatalf("stream accepted after revocation: %v staged=%v checks=%d", err, repository.staged, authority.calls)
	}
}
