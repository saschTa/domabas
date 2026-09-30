package interfaces

import (
	"context"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

type InvoiceRepository interface {
	FilterValues(context.Context, document.DocumentActor, m.InvoiceFilterValueQuery) (m.InvoiceFilterValuePage, error)
	List(context.Context, document.DocumentActor, m.InvoiceQuery) (m.InvoicePage, error)
	Get(context.Context, document.DocumentActor, string) (m.Invoice, error)
	Work(context.Context, document.DocumentJob) (m.InvoiceWork, error)
	BeginWork(context.Context, m.InvoiceWork) error
	Save(context.Context, m.InvoiceWork, *m.Invoice) error
	SaveClassification(context.Context, m.InvoiceWork, m.InvoiceClassification) error
}
type InvoiceExtractor interface {
	Structured(context.Context, []byte) (*m.Invoice, error)
	Infer(context.Context, document.DocumentLLMConfiguration, string, string) (*m.Invoice, error)
	InferClassified(context.Context, document.DocumentLLMConfiguration, string, string) (*m.Invoice, error)
}
type InvoiceClassifier interface {
	Classify(context.Context, document.DocumentLLMConfiguration, string, m.InvoiceClassificationInput) (m.InvoiceClassification, error)
}
type InvoiceCredentials interface {
	PropertyCredential(context.Context, string) (string, error)
}
