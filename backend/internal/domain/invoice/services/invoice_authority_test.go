package services

import (
	"context"
	"errors"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"testing"
)

type invoiceTestAuthority struct{}

func (invoiceTestAuthority) ResolveAuthority(context.Context, i.IdentityPrincipal) (i.IdentityPrincipal, error) {
	return i.IdentityPrincipal{}, i.ErrUnauthorized
}
func TestInvoiceServiceDeniesBeforeRepository(t *testing.T) {
	s := NewInvoiceService(nil, nil, nil, invoiceTestAuthority{}, nil)
	if _, err := s.FilterValues(t.Context(), d.DocumentActor{}, m.InvoiceFilterValueQuery{Limit: 20, Field: "seller"}); !errors.Is(err, m.ErrForbidden) {
		t.Fatal(err)
	}
	if _, err := s.List(t.Context(), d.DocumentActor{}, m.InvoiceQuery{}); !errors.Is(err, m.ErrForbidden) {
		t.Fatal(err)
	}
	if _, err := s.Get(t.Context(), d.DocumentActor{}, "invoice"); !errors.Is(err, m.ErrForbidden) {
		t.Fatal(err)
	}
}
