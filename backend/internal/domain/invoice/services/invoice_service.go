package services

import (
	"context"
	"errors"
	"strings"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	p "github.com/domabas/domabas/backend/internal/domain/invoice/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

type InvoiceService struct {
	repository  p.InvoiceRepository
	extractor   p.InvoiceExtractor
	credentials p.InvoiceCredentials
	authority   p.InvoiceAuthority
	classifier  p.InvoiceClassifier
}

func NewInvoiceService(repository p.InvoiceRepository, extractor p.InvoiceExtractor, credentials p.InvoiceCredentials, authority p.InvoiceAuthority, classifier p.InvoiceClassifier) *InvoiceService {
	return &InvoiceService{repository: repository, extractor: extractor, credentials: credentials, authority: authority, classifier: classifier}
}
func (s *InvoiceService) authorize(ctx context.Context, a document.DocumentActor) error {
	if s.authority == nil {
		return m.ErrForbidden
	}
	principal, err := s.authority.ResolveAuthority(ctx, i.IdentityPrincipal{AccountID: a.AccountID, UserID: a.UserID, SessionDigest: a.SessionDigest, CredentialRevision: a.CredentialRevision})
	if errors.Is(err, i.ErrUnauthorized) || errors.Is(err, i.ErrForbidden) || errors.Is(err, i.ErrPasswordChange) {
		return m.ErrForbidden
	}
	if err != nil {
		return err
	}
	if !principal.HasPermission(i.IdentityPermission("invoices:read")) {
		return m.ErrForbidden
	}
	return nil
}
func (s *InvoiceService) List(ctx context.Context, a document.DocumentActor, q m.InvoiceQuery) (m.InvoicePage, error) {
	if err := s.authorize(ctx, a); err != nil {
		return m.InvoicePage{}, err
	}
	if err := q.Validate(); err != nil {
		return m.InvoicePage{}, err
	}
	return s.repository.List(ctx, a, q)
}
func (s *InvoiceService) Get(ctx context.Context, a document.DocumentActor, id string) (m.Invoice, error) {
	if err := s.authorize(ctx, a); err != nil {
		return m.Invoice{}, err
	}
	return s.repository.Get(ctx, a, id)
}
func (s *InvoiceService) ExtractInvoice(ctx context.Context, job document.DocumentJob) error {
	w, err := s.Work(ctx, job)
	if err != nil || w.Done {
		return err
	}
	if w.SourceFailureCode != "" {
		return document.DocumentProcessingError{Code: w.SourceFailureCode}
	}
	var invoice *m.Invoice
	if len(w.XML) > 0 {
		invoice, err = s.extractor.Structured(ctx, w.XML)
	} else if (w.MediaType == "application/pdf" || w.MediaType == "message/rfc822") && w.Configuration.InvoiceExtractionEnabled() && strings.TrimSpace(w.Text) != "" {
		key, keyErr := s.credentials.PropertyCredential(ctx, w.Configuration.CredentialID)
		if keyErr != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return document.DocumentProcessingError{Code: "configuration_unavailable"}
		}
		if w.ClassifierVersion == m.InvoiceClassifierVersion {
			w, err = s.classify(ctx, w, key)
			if err != nil {
				return err
			}
			if w.Classification.Decision != "invoice" {
				w.Skipped = true
				return s.Save(ctx, w, nil)
			}
			invoice, err = s.extractor.InferClassified(ctx, w.Configuration.Defaults(), key, w.Text)
		} else {
			invoice, err = s.extractor.Infer(ctx, w.Configuration.Defaults(), key, w.Text)
		}
	}
	if len(w.XML) == 0 && w.ClassifierVersion == m.InvoiceClassifierVersion && w.Configuration.InvoiceExtractionEnabled() && (w.MediaType == "application/pdf" || w.MediaType == "message/rfc822") && strings.TrimSpace(w.Text) == "" {
		w, err = s.classify(ctx, w, "")
		if err != nil {
			return err
		}
	}
	if job.AIAttempt > 0 && len(w.XML) == 0 && (!(w.MediaType == "application/pdf" || w.MediaType == "message/rfc822") || !w.Configuration.InvoiceExtractionEnabled() || strings.TrimSpace(w.Text) == "") {
		w.Skipped = true
	}
	if err != nil {
		return err
	}
	return s.Save(ctx, w, invoice)
}

func (s *InvoiceService) classify(ctx context.Context, work m.InvoiceWork, key string) (m.InvoiceWork, error) {
	for work.Classification.Pass == 0 || m.InvoiceClassificationNeedsWiderInput(work.Classification) {
		input := m.SelectInvoiceClassificationInput(work.Text, work.Classification.Pass+1)
		result := m.InvoiceClassification{Decision: "uncertain", Reason: "insufficient_text", InputCharacters: input.InputCharacters, SourceCharacters: input.SourceCharacters, Pass: input.Pass}
		if m.InvoiceClassificationTextUsable(work.Text) {
			if s.classifier == nil {
				return work, document.DocumentProcessingError{Code: "configuration_unavailable"}
			}
			var err error
			result, err = s.classifier.Classify(ctx, work.Configuration.Defaults(), key, input)
			if err != nil {
				return work, err
			}
		}
		if result.Validate() != nil || result.Pass != input.Pass || result.InputCharacters != input.InputCharacters || result.SourceCharacters != input.SourceCharacters {
			return work, document.DocumentProcessingError{Code: "invalid_classification"}
		}
		result = m.FinalizeInvoiceClassification(result, work.ExistingSource)
		if err := s.repository.SaveClassification(ctx, work, result); err != nil {
			return work, err
		}
		work.Classification = result
	}
	return work, nil
}

func (s *InvoiceService) Work(ctx context.Context, job document.DocumentJob) (m.InvoiceWork, error) {
	work, err := s.repository.Work(ctx, job)
	if err != nil || work.Done {
		return work, err
	}
	work, err = m.PlanInvoiceWork(work)
	if err != nil {
		return m.InvoiceWork{}, err
	}
	if err = s.repository.BeginWork(ctx, work); err != nil {
		return m.InvoiceWork{}, err
	}
	return work, nil
}

func (s *InvoiceService) Save(ctx context.Context, work m.InvoiceWork, invoice *m.Invoice) error {
	work, invoice, err := m.PlanInvoiceSave(work, invoice)
	if err != nil {
		return err
	}
	return s.repository.Save(ctx, work, invoice)
}

func (s *InvoiceService) FilterValues(ctx context.Context, a document.DocumentActor, q m.InvoiceFilterValueQuery) (m.InvoiceFilterValuePage, error) {
	if err := s.authorize(ctx, a); err != nil {
		return m.InvoiceFilterValuePage{}, err
	}
	if err := q.Validate(); err != nil {
		return m.InvoiceFilterValuePage{}, err
	}
	return s.repository.FilterValues(ctx, a, q)
}
