//go:build integration

package repos

import (
	"errors"
	"strings"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
)

func TestEmailJobStatusFiltersBeforePaginationAndBindsCursor(t *testing.T) {
	pool, _, repository, owner := independentEmailFixture(t)
	provider := independentProvider(t, repository, owner)
	if _, err := independentEmailService(t, pool, repository).Start(t.Context(), owner, provider.ID, m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: provider.Revision}); err != nil {
		t.Fatal(err)
	}
	for _, status := range []string{"succeeded", "failed", "partial", "cancelled", "superseded"} {
		if _, err := pool.Exec(t.Context(), `INSERT INTO email_runs(id,provider_id,account_id,owner_id,provider_revision,source_generation,trigger,status,created_at)
SELECT gen_random_uuid(),$1,$2,$3,1,1,'scheduled',$4,'2000-01-01' FROM generate_series(1,3)`, provider.ID, owner.AccountID, owner.UserID, status); err != nil {
			t.Fatal(err)
		}
		for _, providerID := range []string{"", provider.ID} {
			q := m.EmailRunQuery{ProviderID: providerID, Limit: 2, Status: status}
			page, err := repository.Runs(t.Context(), owner, q)
			if err != nil || len(page.Items) != 2 || page.NextCursor == "" {
				t.Fatalf("filtered first page %s: %+v %v", status, page, err)
			}
			counts := map[string]int64{}
			for _, group := range page.Counts {
				counts[group.Status] = group.Count
			}
			if counts[status] != 3 || counts["queued"] != 1 {
				t.Fatalf("totals followed page or status filter: %v", counts)
			}
			for _, run := range page.Items {
				if run.Status != status {
					t.Fatalf("wrong status: %+v", run)
				}
			}
			q.Cursor = page.NextCursor
			next, err := repository.Runs(t.Context(), owner, q)
			if err != nil || len(next.Items) != 1 || next.NextCursor != "" || next.Items[0].Status != status || next.Items[0].ID == page.Items[1].ID {
				t.Fatalf("filtered next page: %+v %v", next, err)
			}
			q.Status = "queued"
			if _, err := repository.Runs(t.Context(), owner, q); err == nil {
				t.Fatal("cursor accepted after status changed")
			}
		}
	}
	if _, err := repository.Runs(t.Context(), owner, m.EmailRunQuery{Limit: 20, Status: "unknown"}); err == nil {
		t.Fatal("unknown status accepted")
	}
}

func TestEmailJobsOwnerLibraryPaginationAndDeletedProvider(t *testing.T) {
	pool, _, repository, owner := independentEmailFixture(t)
	first := independentProvider(t, repository, owner)
	second := independentProvider(t, repository, owner)
	foreign := independentEmailActor(t, pool, owner.AccountID)
	foreignProvider := independentProvider(t, repository, foreign)
	other := owner
	other.AccountID = uuid.NewString()
	other.SessionDigest = strings.Repeat("a", 64)
	if _, err := pool.Exec(t.Context(), `INSERT INTO accounts(id,name) VALUES($1,'Other library')`, other.AccountID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(t.Context(), `INSERT INTO memberships(account_id,user_id,role,enabled,is_owner,claims) VALUES($1,$2,'admin',true,true,'{}')`, other.AccountID, owner.UserID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(t.Context(), `INSERT INTO sessions(digest,account_id,user_id,credential_revision,expires_at) VALUES($1,$2,$3,1,clock_timestamp()+interval '1 hour')`, other.SessionDigest, other.AccountID, owner.UserID); err != nil {
		t.Fatal(err)
	}
	otherProvider := independentProvider(t, repository, other)
	for i, provider := range []m.EmailProvider{first, second, foreignProvider, otherProvider} {
		actor := owner
		if i == 2 {
			actor = foreign
		}
		if i == 3 {
			actor = other
		}
		if _, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, provider.ID, m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: provider.Revision}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := pool.Exec(t.Context(), `UPDATE email_runs SET created_at='2026-09-19T00:00:00Z'`); err != nil {
		t.Fatal(err)
	}
	if err := repository.Delete(t.Context(), owner, second.ID, second.Revision); err != nil {
		t.Fatal(err)
	}
	page, err := repository.Runs(t.Context(), owner, m.EmailRunQuery{Limit: 1})
	if err != nil || len(page.Items) != 1 || page.NextCursor == "" {
		t.Fatalf("first private page: %+v %v", page, err)
	}
	next, err := repository.Runs(t.Context(), owner, m.EmailRunQuery{Limit: 1, Cursor: page.NextCursor})
	if err != nil || len(next.Items) != 1 || next.NextCursor != "" || next.Items[0].ID == page.Items[0].ID {
		t.Fatalf("next private page: %+v %v", next, err)
	}
	total := int64(0)
	for _, group := range page.Counts {
		total += group.Count
	}
	if total != 2 {
		t.Fatalf("totals leaked foreign scope or lost deleted provider: %v", page.Counts)
	}
	seen := map[string]bool{}
	for _, run := range append(page.Items, next.Items...) {
		if run.OwnerID != owner.UserID || run.AccountID != owner.AccountID {
			t.Fatalf("foreign job: %+v", run)
		}
		seen[run.ProviderID] = true
	}
	if !seen[first.ID] || !seen[second.ID] {
		t.Fatalf("missing live or deleted provider history: %v", seen)
	}
	for _, actor := range []m.EmailActor{foreign, other} {
		if _, err := repository.Runs(t.Context(), actor, m.EmailRunQuery{Limit: 1, Cursor: page.NextCursor}); err == nil {
			t.Fatal("foreign cursor accepted")
		}
	}
	if _, err := repository.Runs(t.Context(), owner, m.EmailRunQuery{ProviderID: first.ID, Limit: 1, Cursor: page.NextCursor}); err == nil {
		t.Fatal("collection cursor accepted for provider history")
	}
	if _, err := pool.Exec(t.Context(), `UPDATE memberships SET role='viewer',is_owner=false,claims='{}' WHERE account_id=$1 AND user_id=$2`, owner.AccountID, owner.UserID); err != nil {
		t.Fatal(err)
	}
	if _, err := independentEmailService(t, pool, repository).Runs(t.Context(), owner, m.EmailRunQuery{Limit: 20}); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("jobs without email claim: %v", err)
	}
}

func TestEmailFailurePreservesLastRecordedStage(t *testing.T) {
	for _, stage := range []string{"discovering", "fetching", "importing"} {
		t.Run(stage, func(t *testing.T) {
			pool, source, repository, actor := independentEmailFixture(t)
			provider := independentProvider(t, repository, actor)
			attempt := independentAttempt(t, source, repository, actor, provider)
			if err := source.SetStage(t.Context(), attempt, stage); err != nil {
				t.Fatal(err)
			}
			if err := independentPollingService(t, pool, source, repository).Finish(t.Context(), attempt, false, "connection_failed"); err != nil {
				t.Fatal(err)
			}
			run, err := repository.Run(t.Context(), actor, attempt.RunID)
			if err != nil || run.Stage != stage || run.Status != "failed" || run.FailureCode != "connection_failed" || run.FinishedAt == nil {
				t.Fatalf("failure lost stage evidence: %+v %v", run, err)
			}
		})
	}
}
