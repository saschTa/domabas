package services

import (
	"context"
	"errors"
	"io"
	"time"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type DocumentImportService struct {
	repository p.DocumentImportRepository
	store      p.DocumentContentStore
	inspector  p.DocumentEmailInspector
	authority  p.DocumentAuthority
	now        func() time.Time
}

func NewDocumentImportService(repository p.DocumentImportRepository, store p.DocumentContentStore, inspector p.DocumentEmailInspector, authority p.DocumentAuthority, now func() time.Time) *DocumentImportService {
	return &DocumentImportService{repository: repository, store: store, inspector: inspector, authority: authority, now: now}
}
func (s *DocumentImportService) authorize(ctx context.Context, a m.DocumentImportAuthority) (m.DocumentImportAuthority, error) {
	if s.authority == nil {
		return a, m.ErrForbidden
	}
	revision, err := s.repository.ImportConsent(ctx, a)
	if err != nil {
		return a, err
	}
	principal, err := s.authority.ResolveBackgroundAuthority(ctx, a.AccountID, a.OwnerID, revision)
	if err != nil {
		return a, m.ErrForbidden
	}
	for _, claim := range []identity.IdentityPermission{identity.EmailManage, identity.DocumentsRead, identity.DocumentsUpload} {
		if !principal.HasPermission(claim) {
			return a, m.ErrForbidden
		}
	}
	a.CredentialRevision = principal.CredentialRevision
	return a, nil
}
func (s *DocumentImportService) Reserve(ctx context.Context, a m.DocumentImportAuthority) (m.DocumentUploadReservation, error) {
	a, err := s.authorize(ctx, a)
	if err != nil {
		return m.DocumentUploadReservation{}, err
	}
	id, err := documentID()
	if err != nil {
		return m.DocumentUploadReservation{}, err
	}
	return s.repository.ReserveImport(ctx, a, m.DocumentUploadReservation{ID: id, AccountID: a.AccountID, UploaderID: a.OwnerID, ExpiresAt: s.now().UTC().Add(5 * time.Minute)})
}
func (s *DocumentImportService) Stage(ctx context.Context, a m.DocumentImportAuthority, reservation m.DocumentUploadReservation, filename string, reader io.Reader) (m.DocumentMetadata, error) {
	a, err := s.authorize(ctx, a)
	if err != nil {
		return m.DocumentMetadata{}, err
	}
	reference, err := s.store.Stage(ctx, reservation, filename, reader)
	if err != nil {
		return m.DocumentMetadata{}, err
	}
	a, err = s.authorize(ctx, a)
	if err != nil {
		return m.DocumentMetadata{}, err
	}
	if err = s.repository.StageImport(ctx, a, reservation, reference); err != nil {
		return m.DocumentMetadata{}, err
	}
	metadata := m.DocumentMetadata{Title: filename, Kind: "document", Tags: []string{}, Recipients: []string{}, CC: []string{}, BCC: []string{}}
	if reference.File.MediaType == "message/rfc822" {
		original, err := s.store.Open(ctx, reference)
		if err != nil {
			return metadata, err
		}
		defer original.Close()
		return s.inspector.Envelope(original)
	}
	return metadata, nil
}
func (s *DocumentImportService) Accept(ctx context.Context, a m.DocumentImportAuthority, reservation m.DocumentUploadReservation, metadata m.DocumentMetadata) (m.DocumentImportResult, error) {
	a, err := s.authorize(ctx, a)
	if err != nil {
		return m.DocumentImportResult{}, err
	}
	metadata, err = metadata.Normalize()
	if err != nil {
		return m.DocumentImportResult{}, err
	}
	facts, err := s.repository.ImportAcceptanceFacts(ctx, a, reservation)
	if err != nil {
		return m.DocumentImportResult{}, err
	}
	command, err := m.PlanDocumentImportAcceptance(facts, metadata)
	if err != nil {
		return m.DocumentImportResult{}, err
	}
	return s.repository.AcceptImport(ctx, a, reservation, command)
}
func (s *DocumentImportService) Inspect(ctx context.Context, a m.DocumentImportAuthority, visit func(m.DocumentEmailPart) error) (m.DocumentEmailInspection, error) {
	a, err := s.authorize(ctx, a)
	if err != nil {
		return m.DocumentEmailInspection{}, err
	}
	reference, err := s.repository.ImportReference(ctx, a)
	if err != nil {
		return m.DocumentEmailInspection{}, err
	}
	reader, err := s.store.Open(ctx, reference)
	if err != nil {
		reference, err = s.repository.ImportReference(ctx, a)
		if err == nil {
			reader, err = s.store.Open(ctx, reference)
		}
	}
	if err != nil {
		return m.DocumentEmailInspection{}, err
	}
	defer reader.Close()
	if _, err := s.authorize(ctx, a); err != nil {
		return m.DocumentEmailInspection{}, err
	}
	tracked := &documentImportReader{reader: reader}
	result, err := s.inspector.Inspect(ctx, tracked, visit)
	if tracked.failure != nil && ctx.Err() == nil {
		return result, m.DocumentProcessingError{Code: "storage_unavailable", Retryable: true}
	}
	return result, err
}

type documentImportReader struct {
	reader  io.Reader
	failure error
}

func (r *documentImportReader) Read(p []byte) (int, error) {
	n, err := r.reader.Read(p)
	if err != nil && !errors.Is(err, io.EOF) {
		r.failure = err
	}
	return n, err
}
func (s *DocumentImportService) EmailLinks(ctx context.Context, a m.DocumentActor, id string, limit int, cursor string) (m.DocumentEmailLinks, error) {
	if _, err := resolveDocumentAuthority(ctx, s.authority, a, identity.DocumentsRead); err != nil {
		return m.DocumentEmailLinks{}, err
	}
	return s.repository.EmailLinks(ctx, a, id, limit, cursor)
}
func (s *DocumentImportService) EmailParents(ctx context.Context, a m.DocumentActor, id string, limit int, cursor string) (m.DocumentEmailParents, error) {
	if _, err := resolveDocumentAuthority(ctx, s.authority, a, identity.DocumentsRead); err != nil {
		return m.DocumentEmailParents{}, err
	}
	return s.repository.EmailParents(ctx, a, id, limit, cursor)
}
