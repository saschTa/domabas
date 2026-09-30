package services

import (
	"context"
	"errors"
	"testing"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	p "github.com/domabas/domabas/backend/internal/domain/paperless/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type paperlessTestAuthority struct{ denied bool }

func (a paperlessTestAuthority) ResolveAuthority(context.Context, i.IdentityPrincipal) (i.IdentityPrincipal, error) {
	if a.denied {
		return i.IdentityPrincipal{}, i.ErrForbidden
	}
	return i.IdentityPrincipal{Permissions: []i.IdentityPermission{i.PaperlessImport, i.DocumentsRead, i.DocumentsUpload, i.SystemPaperlessManage}}, nil
}
func (a paperlessTestAuthority) ResolveBackgroundAuthority(ctx context.Context, _, _ string, _ int64) (i.IdentityPrincipal, error) {
	return a.ResolveAuthority(ctx, i.IdentityPrincipal{})
}
func (j *mockJobs) WorkIdentity(context.Context, string) (d.DocumentActor, error) {
	return j.work.Actor, j.err
}

func TestPaperlessServiceRejectsBeforeRepositoryCalls(t *testing.T) {
	service := NewPaperlessJobsService(nil, nil, paperlessTestAuthority{denied: true})
	if _, err := service.Get(t.Context(), d.DocumentActor{}, "id"); !errors.Is(err, d.ErrForbidden) {
		t.Fatal(err)
	}
	if _, err := service.Settings(t.Context(), d.DocumentActor{}); !errors.Is(err, d.ErrForbidden) {
		t.Fatal(err)
	}
	if _, err := service.Create(t.Context(), d.DocumentActor{}, "id", m.PaperlessConnection{}); !errors.Is(err, d.ErrForbidden) {
		t.Fatal(err)
	}
}

type paperlessRevocationAuthority struct{ calls int }

func (a *paperlessRevocationAuthority) ResolveAuthority(context.Context, i.IdentityPrincipal) (i.IdentityPrincipal, error) {
	return i.IdentityPrincipal{}, i.ErrForbidden
}
func (a *paperlessRevocationAuthority) ResolveBackgroundAuthority(ctx context.Context, account, user string, revision int64) (i.IdentityPrincipal, error) {
	a.calls++
	return (paperlessTestAuthority{denied: a.calls > 1}).ResolveAuthority(ctx, i.IdentityPrincipal{})
}

func TestPaperlessDiscoveryReauthorizesAfterRemoteRead(t *testing.T) {
	store := &mockJobs{work: m.PaperlessWork{Run: m.PaperlessRun{State: "running", Stage: "discovering"}, Page: 1}}
	remote := &mockRepository{page: m.PaperlessPage{Total: 0}}
	service := NewPaperlessJobsService(store, NewPaperlessImportService(remote, nil), &paperlessRevocationAuthority{})
	done, err := service.Step(t.Context(), "run")
	if err != nil || !done || store.pageCalls != 0 || store.code != "permission_revoked" {
		t.Fatalf("done=%v err=%v store=%+v", done, err, store)
	}
}

var _ p.PaperlessAuthority = paperlessTestAuthority{}
