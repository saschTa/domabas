package services

import (
	"context"
	"errors"
	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"strings"
	"testing"
)

type thumbnailReadRepository struct {
	p.DocumentThumbnailRepository
	reads     int
	afterRead func()
}

func (r *thumbnailReadRepository) ReadThumbnail(_ context.Context, _ m.DocumentActor, _ string, sha string) (m.DocumentThumbnailContent, error) {
	r.reads++
	if r.afterRead != nil {
		r.afterRead()
	}
	return m.DocumentThumbnailContent{Descriptor: m.DocumentThumbnail{SHA256: sha}, Bytes: []byte("protected thumbnail bytes")}, nil
}
func thumbnailReadActor() m.DocumentActor {
	return m.DocumentActor{AccountID: "ed859553-34d3-4d90-870f-c5e8324b2c50", UserID: "94d9a45a-d2c2-471c-957f-1a8150fdc907", SessionDigest: "digest", CredentialRevision: 1}
}
func TestThumbnailReadRequiresBothCurrentClaimsBeforeContentIO(t *testing.T) {
	for _, scenario := range []struct {
		name        string
		permissions []identity.IdentityPermission
		allowed     bool
	}{
		{name: "no claims"},
		{name: "thumbnail without original content", permissions: []identity.IdentityPermission{identity.DocumentsThumbnailsRead}},
		{name: "original content without thumbnail", permissions: []identity.IdentityPermission{identity.DocumentsDownload}},
		{name: "metadata only", permissions: []identity.IdentityPermission{identity.DocumentsRead}},
		{name: "both content claims", permissions: []identity.IdentityPermission{identity.DocumentsThumbnailsRead, identity.DocumentsDownload}, allowed: true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			repository := &thumbnailReadRepository{}
			authority := &documentTestAuthority{principal: identity.IdentityPrincipal{Role: identity.Admin, IsOwner: true, Claims: []identity.IdentityPermission{identity.DocumentsThumbnailsRead, identity.DocumentsDownload}, Permissions: scenario.permissions}}
			service := NewDocumentThumbnailService(repository, nil, nil, authority)
			result, err := service.Read(t.Context(), thumbnailReadActor(), "document", strings.Repeat("a", 64))
			if scenario.allowed {
				if err != nil || repository.reads != 1 || authority.calls != 2 || len(result.Bytes) == 0 {
					t.Fatalf("authorized read=%+v error=%v reads=%d checks=%d", result, err, repository.reads, authority.calls)
				}
				return
			}
			if !errors.Is(err, m.ErrForbidden) || repository.reads != 0 || authority.calls != 1 || len(result.Bytes) != 0 {
				t.Fatalf("denied read disclosed content: error=%v reads=%d checks=%d bytes=%d", err, repository.reads, authority.calls, len(result.Bytes))
			}
		})
	}
}
func TestThumbnailReadRechecksAuthorityAfterContentIO(t *testing.T) {
	for _, scenario := range []struct {
		name   string
		revoke func(*documentTestAuthority)
		want   error
	}{
		{name: "thumbnail grant revoked", revoke: func(a *documentTestAuthority) {
			a.principal.Permissions = []identity.IdentityPermission{identity.DocumentsDownload}
		}, want: m.ErrForbidden},
		{name: "download grant revoked", revoke: func(a *documentTestAuthority) {
			a.principal.Permissions = []identity.IdentityPermission{identity.DocumentsThumbnailsRead}
		}, want: m.ErrForbidden},
		{name: "session revoked", revoke: func(a *documentTestAuthority) { a.err = identity.ErrUnauthorized }, want: m.ErrUnauthorized},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			authority := &documentTestAuthority{principal: identity.IdentityPrincipal{Permissions: []identity.IdentityPermission{identity.DocumentsThumbnailsRead, identity.DocumentsDownload}}}
			repository := &thumbnailReadRepository{afterRead: func() { scenario.revoke(authority) }}
			service := NewDocumentThumbnailService(repository, nil, nil, authority)
			result, err := service.Read(t.Context(), thumbnailReadActor(), "document", strings.Repeat("a", 64))
			if !errors.Is(err, scenario.want) || repository.reads != 1 || authority.calls != 2 || len(result.Bytes) != 0 || result.Descriptor.SHA256 != "" {
				t.Fatalf("revocation disclosure: error=%v reads=%d checks=%d result=%+v", err, repository.reads, authority.calls, result)
			}
		})
	}
}
