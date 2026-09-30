//go:build integration

package repos_test

import (
	"errors"
	"strings"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

func TestPaperlessBackgroundAcceptanceSurvivesLogoutButFencesCancellationAndClaims(t *testing.T) {
	f := newIngestionFixture(t)
	actor := f.actor
	actor.ImportRunID = uuid.NewString()
	actor.ImportSourceID = 1
	actor.ImportClaimToken = uuid.NewString()
	f.exec(t, "INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,state,stage,task_queue) VALUES($1,$2,$3,1,'https://paperless.example.test','hash','running','importing','test-owned')", actor.ImportRunID, actor.AccountID, actor.UserID)
	f.exec(t, "INSERT INTO paperless_items(run_id,source_id,title,claim_token,claim_deadline,claim_recover_after) VALUES($1,1,'Source',$2,clock_timestamp()+interval '60 seconds',clock_timestamp()+interval '120 seconds')", actor.ImportRunID, actor.ImportClaimToken)
	f.exec(t, "DELETE FROM sessions WHERE digest=$1", actor.SessionDigest)
	accepted := f.accept(t, actor, strings.Repeat("a", 64), "Background original")
	if accepted.ID == "" {
		t.Fatal("logout revoked explicit job consent")
	}
	reservation := f.stage(t, actor, strings.Repeat("b", 64))
	f.exec(t, "UPDATE paperless_items SET claim_token=$2 WHERE run_id=$1", actor.ImportRunID, uuid.NewString())
	if _, err := f.acceptReservation(t.Context(), actor, reservation.ID, m.DocumentMetadata{Title: "Stale claim", Kind: "document"}, accepted.CreatedAt); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("reassigned claim accepted: %v", err)
	}
	f.exec(t, "UPDATE paperless_items SET claim_token=NULL,claim_deadline=NULL,claim_recover_after=NULL WHERE run_id=$1", actor.ImportRunID)
	if _, err := f.acceptReservation(t.Context(), actor, reservation.ID, m.DocumentMetadata{Title: "Released claim", Kind: "document"}, accepted.CreatedAt); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("released claim accepted: %v", err)
	}
	f.exec(t, "UPDATE paperless_items SET claim_token=$2,claim_deadline=clock_timestamp()+interval '60 seconds',claim_recover_after=clock_timestamp()+interval '120 seconds' WHERE run_id=$1", actor.ImportRunID, actor.ImportClaimToken)
	f.exec(t, "UPDATE paperless_runs SET cancel_requested=true WHERE id=$1", actor.ImportRunID)
	if _, err := f.acceptReservation(t.Context(), actor, reservation.ID, m.DocumentMetadata{Title: "Cancelled", Kind: "document"}, accepted.CreatedAt); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("cancelled import accepted: %v", err)
	}
	f.exec(t, "UPDATE paperless_runs SET cancel_requested=false WHERE id=$1", actor.ImportRunID)
	f.exec(t, "UPDATE memberships SET is_owner=false,role='viewer',claims=ARRAY['documents:upload'] WHERE account_id=$1 AND user_id=$2", actor.AccountID, actor.UserID)
	if _, err := f.acceptReservation(t.Context(), actor, reservation.ID, m.DocumentMetadata{Title: "Revoked", Kind: "document"}, accepted.CreatedAt); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("revoked import claim accepted: %v", err)
	}
	f.exec(t, "UPDATE memberships SET is_owner=true,role='admin' WHERE account_id=$1 AND user_id=$2", actor.AccountID, actor.UserID)
	f.exec(t, "UPDATE users SET credential_revision=2 WHERE id=$1", actor.UserID)
	if _, err := f.acceptReservation(t.Context(), actor, reservation.ID, m.DocumentMetadata{Title: "Old consent", Kind: "document"}, accepted.CreatedAt); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("old credential consent accepted: %v", err)
	}
}
