package models

import (
	"net/http"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

type InvoiceErrorResponse struct {
	Status        int
	Code, Message string
}

func (r InvoiceErrorResponse) VisitListInvoicesResponse(w http.ResponseWriter) error {
	transport.WriteError(w, r.Status, r.Code, r.Message)
	return nil
}
func (r InvoiceErrorResponse) VisitGetInvoiceResponse(w http.ResponseWriter) error {
	transport.WriteError(w, r.Status, r.Code, r.Message)
	return nil
}

func (r InvoiceErrorResponse) VisitListInvoiceFilterValuesResponse(w http.ResponseWriter) error {
	transport.WriteError(w, r.Status, r.Code, r.Message)
	return nil
}
