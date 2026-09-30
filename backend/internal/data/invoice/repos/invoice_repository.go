package repos

import (
	"context"

	r "github.com/domabas/domabas/backend/internal/data/invoice/models"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

type InvoiceSource interface {
	FilterValues(context.Context, document.DocumentActor, m.InvoiceFilterValueQuery) (m.InvoiceFilterValuePage, error)
	List(context.Context, document.DocumentActor, m.InvoiceQuery) (r.InvoiceRecordPage, error)
	Get(context.Context, document.DocumentActor, string) (r.InvoiceRecord, error)
	Work(context.Context, document.DocumentJob) (m.InvoiceWork, error)
	BeginWork(context.Context, m.InvoiceWork) error
	Save(context.Context, m.InvoiceWork, *r.InvoiceRecord) error
	SaveClassification(context.Context, m.InvoiceWork, m.InvoiceClassification) error
}
type InvoiceRepository struct{ source InvoiceSource }

func NewInvoiceRepository(source InvoiceSource) *InvoiceRepository { return &InvoiceRepository{source} }
func (r *InvoiceRepository) List(ctx context.Context, a document.DocumentActor, q m.InvoiceQuery) (m.InvoicePage, error) {
	page, err := r.source.List(ctx, a, q)
	result := m.InvoicePage{Items: []m.Invoice{}, NextCursor: page.NextCursor}
	if err != nil {
		return result, err
	}
	for _, record := range page.Items {
		result.Items = append(result.Items, invoiceRecordToDomainMapper(record))
	}
	return result, nil
}
func (r *InvoiceRepository) Get(ctx context.Context, a document.DocumentActor, id string) (m.Invoice, error) {
	v, err := r.source.Get(ctx, a, id)
	if err != nil {
		return m.Invoice{}, err
	}
	return invoiceRecordToDomainMapper(v), nil
}
func (r *InvoiceRepository) Work(ctx context.Context, j document.DocumentJob) (m.InvoiceWork, error) {
	return r.source.Work(ctx, j)
}
func (r *InvoiceRepository) BeginWork(ctx context.Context, w m.InvoiceWork) error {
	return r.source.BeginWork(ctx, w)
}
func (r *InvoiceRepository) SaveClassification(ctx context.Context, w m.InvoiceWork, classification m.InvoiceClassification) error {
	return r.source.SaveClassification(ctx, w, classification)
}
func (r *InvoiceRepository) Save(ctx context.Context, w m.InvoiceWork, v *m.Invoice) error {
	if v == nil {
		return r.source.Save(ctx, w, nil)
	}
	record := invoiceDomainToRecordMapper(*v)
	return r.source.Save(ctx, w, &record)
}

func (r *InvoiceRepository) FilterValues(ctx context.Context, a document.DocumentActor, q m.InvoiceFilterValueQuery) (m.InvoiceFilterValuePage, error) {
	return r.source.FilterValues(ctx, a, q)
}
