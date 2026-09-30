//go:build integration

package repos_test

import (
	"errors"
	"fmt"
	"github.com/domabas/domabas/backend/internal/domain/document/services"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/document/datasources"
	"github.com/domabas/domabas/backend/internal/data/document/repos"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

func TestEmailLinksPreserveMultipleParentsNumericPagingAndLiveAuthority(t *testing.T) {
	f := newIngestionFixture(t)
	repository := services.NewDocumentImportService(repos.NewDocumentImportRepository(datasources.NewDocumentIngestionDataSource(f.source.Database(), fixturePublication{}, f.scheduler)), nil, nil, f.authority, time.Now)
	a := f.actor
	parent := f.accept(t, a, strings.Repeat("1", 64), "Parent one")
	second := f.accept(t, a, strings.Repeat("2", 64), "Parent two")
	child := f.accept(t, a, strings.Repeat("3", 64), "Shared attachment")
	foreign := f.addActor(t)
	foreignParent := f.accept(t, foreign, strings.Repeat("4", 64), "Private parent")
	message := func(actor m.DocumentActor, parentID string) string {
		id := uuid.NewString()
		f.exec(t, `INSERT INTO email_messages(id,provider_id,account_id,owner_id,source_generation,mailbox_generation,uid,run_id,provider_revision,state,parent_document_id) VALUES($1,$2,$3,$4,1,1,1,$5,1,'accepted',$6)`, id, uuid.NewString(), actor.AccountID, actor.UserID, uuid.NewString(), parentID)
		return id
	}
	part := func(actor m.DocumentActor, messageID, path, state string, document any) {
		f.exec(t, `INSERT INTO email_parts(id,message_id,account_id,path,filename,media_type,state,document_id) VALUES($1,$2,$3,$4,$5,'application/pdf',$6,$7)`, uuid.NewString(), messageID, actor.AccountID, path, fmt.Sprintf("part-%s.pdf", path), state, document)
	}
	one := message(a, parent.ID)
	for _, path := range []string{"10", "2", "1.2"} {
		part(a, one, path, "accepted", child.ID)
	}
	duplicate := message(a, parent.ID)
	part(a, duplicate, "2", "pending", nil)
	part(a, message(a, second.ID), "1", "reused", child.ID)
	part(foreign, message(foreign, foreignParent.ID), "1", "accepted", child.ID)
	page, err := repository.EmailLinks(t.Context(), a, parent.ID, 1, "")
	if err != nil || len(page.Attachments) != 1 || page.Attachments[0].Part != "1.2" || page.NextCursor == "" {
		t.Fatalf("first numeric page: %+v %v", page, err)
	}
	if _, err = repository.EmailLinks(t.Context(), a, second.ID, 1, page.NextCursor); err == nil {
		t.Fatal("cursor crossed its parent scope")
	}
	if _, err = repository.EmailLinks(t.Context(), a, parent.ID, 2, page.NextCursor); err == nil {
		t.Fatal("cursor crossed its page-size scope")
	}
	page, err = repository.EmailLinks(t.Context(), a, parent.ID, 1, page.NextCursor)
	if err != nil || len(page.Attachments) != 1 || page.Attachments[0].Part != "2" || page.Attachments[0].Document == nil || page.Attachments[0].Status != "accepted" {
		t.Fatalf("pending duplicate displaced committed edge: %+v %v", page, err)
	}
	page, err = repository.EmailLinks(t.Context(), a, parent.ID, 1, page.NextCursor)
	if err != nil || len(page.Attachments) != 1 || page.Attachments[0].Part != "10" || page.NextCursor != "" {
		t.Fatalf("last numeric page: %+v %v", page, err)
	}
	parents, err := repository.EmailParents(t.Context(), a, child.ID, 1, "")
	if err != nil || len(parents.Items) != 1 || parents.Items[0].DocumentID != second.ID || parents.NextCursor == "" {
		t.Fatalf("parents newest: %+v %v", parents, err)
	}
	if _, err = repository.EmailParents(t.Context(), a, parent.ID, 1, parents.NextCursor); err == nil {
		t.Fatal("parent cursor crossed child scope")
	}
	parents, err = repository.EmailParents(t.Context(), a, child.ID, 1, parents.NextCursor)
	if err != nil || len(parents.Items) != 1 || parents.Items[0].DocumentID != parent.ID || parents.NextCursor != "" {
		t.Fatalf("parents did not deduplicate or leaked other library: %+v %v", parents, err)
	}
	if _, err = repository.EmailLinks(t.Context(), foreign, parent.ID, 20, ""); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("foreign parent lookup: %v", err)
	}
	if err = f.service.Delete(t.Context(), a, child.ID); err != nil {
		t.Fatal(err)
	}
	page, err = repository.EmailLinks(t.Context(), a, parent.ID, 20, "")
	if err != nil || len(page.Attachments) != 3 {
		t.Fatalf("deleted attachment edges: %+v %v", page, err)
	}
	for _, item := range page.Attachments {
		if item.Document != nil || item.Status != "deleted" {
			t.Fatalf("deleted target leaked identity/title: %+v", item)
		}
	}
	if _, err = repository.EmailParents(t.Context(), a, child.ID, 20, ""); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("deleted current document: %v", err)
	}
	f.exec(t, `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, a.AccountID, a.UserID)
	if _, err = repository.EmailLinks(t.Context(), a, parent.ID, 20, ""); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("system admin bypassed disabled membership: %v", err)
	}
}
