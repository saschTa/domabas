package routes

import (
	"net/http"

	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

type validatedInvoiceServer struct{ contract.ServerInterface }

func Register(server contract.ServerInterface, guard *transport.HTTPIdentityGuard) (contract.ServerInterface, []routing.HTTPRouteGroup) {
	return &validatedInvoiceServer{server}, []routing.HTTPRouteGroup{{Prefix: "/api/v1/invoices", Middleware: []routing.HTTPMiddleware{guard.Require(identity.InvoicesRead)}}}
}

func validInvoiceQuery(w http.ResponseWriter, r *http.Request, allowed map[string]bool) bool {
	for name, values := range r.URL.Query() {
		if !allowed[name] || len(values) != 1 || (values[0] == "" && name != "q") {
			transport.WriteError(w, 400, "invalid_request", "invoice query values must be known, unique and valid")
			return false
		}
	}
	return true
}
func (s *validatedInvoiceServer) ListInvoices(w http.ResponseWriter, r *http.Request, p contract.ListInvoicesParams) {
	if !validInvoiceQuery(w, r, map[string]bool{"limit": true, "cursor": true, "source": true, "q": true, "sort": true, "number": true, "seller": true, "buyer": true, "currency": true, "typeCode": true, "format": true, "paymentMeansCode": true, "createdFrom": true, "createdTo": true, "issueFrom": true, "issueTo": true, "dueFrom": true, "dueTo": true, "totalMin": true, "totalMax": true}) {
		return
	}
	s.ServerInterface.ListInvoices(w, r, p)
}
func (s *validatedInvoiceServer) ListInvoiceFilterValues(w http.ResponseWriter, r *http.Request, p contract.ListInvoiceFilterValuesParams) {
	if !validInvoiceQuery(w, r, map[string]bool{"limit": true, "cursor": true, "field": true, "q": true}) {
		return
	}
	s.ServerInterface.ListInvoiceFilterValues(w, r, p)
}
