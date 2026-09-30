package handlers

import (
	"context"
	"errors"
	"log/slog"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	responses "github.com/domabas/domabas/backend/internal/presentation/invoice/models"
)

type InvoiceService interface {
	FilterValues(context.Context, document.DocumentActor, m.InvoiceFilterValueQuery) (m.InvoiceFilterValuePage, error)
	List(context.Context, document.DocumentActor, m.InvoiceQuery) (m.InvoicePage, error)
	Get(context.Context, document.DocumentActor, string) (m.Invoice, error)
}
type InvoiceHandler struct {
	service InvoiceService
	logger  *slog.Logger
}

func NewInvoiceHandler(service InvoiceService, logger *slog.Logger) *InvoiceHandler {
	return &InvoiceHandler{service, logger}
}
func actor(ctx context.Context) document.DocumentActor {
	p, _ := transport.Principal(ctx)
	return document.DocumentActor{AccountID: p.AccountID, UserID: p.UserID, SessionDigest: p.SessionDigest, CredentialRevision: p.CredentialRevision}
}
func (h *InvoiceHandler) failure(ctx context.Context, err error) responses.InvoiceErrorResponse {
	switch {
	case errors.Is(err, m.ErrInvalid):
		return responses.InvoiceErrorResponse{Status: 400, Code: "invalid_request", Message: "invalid invoice query"}
	case errors.Is(err, m.ErrForbidden):
		return responses.InvoiceErrorResponse{Status: 403, Code: "forbidden", Message: "permission denied"}
	case errors.Is(err, m.ErrNotFound):
		return responses.InvoiceErrorResponse{Status: 404, Code: "not_found", Message: "invoice unavailable"}
	}
	h.logger.ErrorContext(ctx, "invoice operation failed")
	return responses.InvoiceErrorResponse{Status: 500, Code: "internal_error", Message: "invoice operation failed"}
}
func (h *InvoiceHandler) ListInvoices(ctx context.Context, r contract.ListInvoicesRequestObject) (contract.ListInvoicesResponseObject, error) {
	q := m.InvoiceQuery{Limit: 20}
	if r.Params.Limit != nil {
		q.Limit = *r.Params.Limit
	}
	if r.Params.Cursor != nil {
		q.Cursor = *r.Params.Cursor
	}
	if r.Params.Source != nil {
		q.Source = string(*r.Params.Source)
	}
	if r.Params.Q != nil {
		q.Text = *r.Params.Q
	}
	if r.Params.Sort != nil {
		q.Sort = string(*r.Params.Sort)
	}
	if r.Params.Number != nil {
		q.Number = *r.Params.Number
	}
	if r.Params.Seller != nil {
		q.Seller = *r.Params.Seller
	}
	if r.Params.Buyer != nil {
		q.Buyer = *r.Params.Buyer
	}
	if r.Params.Currency != nil {
		q.Currency = *r.Params.Currency
	}
	if r.Params.TypeCode != nil {
		q.TypeCode = *r.Params.TypeCode
	}
	if r.Params.Format != nil {
		q.Format = *r.Params.Format
	}
	if r.Params.PaymentMeansCode != nil {
		q.PaymentMeansCode = *r.Params.PaymentMeansCode
	}
	if r.Params.CreatedFrom != nil {
		q.CreatedFrom = *r.Params.CreatedFrom
	}
	if r.Params.CreatedTo != nil {
		q.CreatedTo = *r.Params.CreatedTo
	}
	if r.Params.IssueFrom != nil {
		q.IssueFrom = *r.Params.IssueFrom
	}
	if r.Params.IssueTo != nil {
		q.IssueTo = *r.Params.IssueTo
	}
	if r.Params.DueFrom != nil {
		q.DueFrom = *r.Params.DueFrom
	}
	if r.Params.DueTo != nil {
		q.DueTo = *r.Params.DueTo
	}
	if r.Params.TotalMin != nil {
		q.TotalMin = *r.Params.TotalMin
	}
	if r.Params.TotalMax != nil {
		q.TotalMax = *r.Params.TotalMax
	}
	page, err := h.service.List(ctx, actor(ctx), q)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	out := contract.InvoicePage{Items: []contract.Invoice{}}
	for _, v := range page.Items {
		out.Items = append(out.Items, invoiceResponseMapper(v))
	}
	if page.NextCursor != "" {
		out.NextCursor = &page.NextCursor
	}
	return contract.ListInvoices200JSONResponse(out), nil
}
func (h *InvoiceHandler) GetInvoice(ctx context.Context, r contract.GetInvoiceRequestObject) (contract.GetInvoiceResponseObject, error) {
	v, err := h.service.Get(ctx, actor(ctx), r.Id.String())
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.GetInvoice200JSONResponse(invoiceResponseMapper(v)), nil
}

func (h *InvoiceHandler) ListInvoiceFilterValues(ctx context.Context, r contract.ListInvoiceFilterValuesRequestObject) (contract.ListInvoiceFilterValuesResponseObject, error) {
	q := m.InvoiceFilterValueQuery{Limit: 20, Field: string(r.Params.Field)}
	if r.Params.Limit != nil {
		q.Limit = *r.Params.Limit
	}
	if r.Params.Cursor != nil {
		q.Cursor = *r.Params.Cursor
	}
	if r.Params.Q != nil {
		q.Text = *r.Params.Q
	}
	page, err := h.service.FilterValues(ctx, actor(ctx), q)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	out := contract.InvoiceFilterValuePage{Items: page.Items}
	if page.NextCursor != "" {
		out.NextCursor = &page.NextCursor
	}
	return contract.ListInvoiceFilterValues200JSONResponse(out), nil
}
