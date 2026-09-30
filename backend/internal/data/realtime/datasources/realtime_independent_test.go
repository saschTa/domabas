//go:build integration

package datasources_test

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/identity/security"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/data/realtime/datasources"
	"github.com/domabas/domabas/backend/internal/data/realtime/repos"
	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
	"github.com/domabas/domabas/backend/internal/domain/realtime/services"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type independentRealtimeFixture struct {
	pool                                   *pgxpool.Pool
	listener                               *pgx.Conn
	service                                *services.RealtimeService
	schema, channel, account, otherAccount string
	owner, peer, manager, outsider         m.RealtimeSubject
}

func newIndependentRealtimeFixture(t *testing.T) *independentRealtimeFixture {
	t.Helper()
	databaseURL := testdb.New(t)
	source, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(source.Close)
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	pool, err := pgxpool.New(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	f := &independentRealtimeFixture{pool: pool, account: uuid.NewString(), otherAccount: uuid.NewString()}
	policy, err := security.NewCasbinIdentityAuthorizer()
	if err != nil {
		t.Fatal(err)
	}
	f.service = services.NewRealtimeService(repos.NewRealtimeAuthorityRepository(datasources.NewRealtimeAuthorityDataSource(source.Database())), nil, policy)
	tx, err := pool.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(context.Background()) }()
	if _, err = tx.Exec(t.Context(), `INSERT INTO accounts(id,name) VALUES($1,'Shared A'),($2,'Shared B')`, f.account, f.otherAccount); err != nil {
		t.Fatal(err)
	}
	actors := []*m.RealtimeSubject{&f.owner, &f.peer, &f.manager, &f.outsider}
	for index, actor := range actors {
		personal := uuid.NewString()
		*actor = m.RealtimeSubject{UserID: uuid.NewString(), AccountID: f.account, SessionDigest: strings.Repeat(fmt.Sprint(index+1), 64), CredentialRevision: 1}
		if index == 3 {
			actor.AccountID = f.otherAccount
		}
		if _, err = tx.Exec(t.Context(), `INSERT INTO accounts(id,name) VALUES($1,'Personal');`, personal); err != nil {
			t.Fatal(err)
		}
		if _, err = tx.Exec(t.Context(), `INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,$2,'fixture-only',$3)`, actor.UserID, fmt.Sprintf("realtime-%d@example.test", index), personal); err != nil {
			t.Fatal(err)
		}
		if _, err = tx.Exec(t.Context(), `INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)`, personal, actor.UserID); err != nil {
			t.Fatal(err)
		}
		role, claims := "viewer", []string{"documents:jobs:read"}
		if index == 0 {
			claims = append(claims, "email:manage")
		}
		if index >= 2 {
			role = "admin"
		}
		if _, err = tx.Exec(t.Context(), `INSERT INTO memberships(account_id,user_id,role,claims) VALUES($1,$2,$3,$4)`, actor.AccountID, actor.UserID, role, claims); err != nil {
			t.Fatal(err)
		}
		if _, err = tx.Exec(t.Context(), `INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)`, actor.SessionDigest, actor.AccountID, actor.UserID); err != nil {
			t.Fatal(err)
		}
	}
	if _, err = tx.Exec(t.Context(), `INSERT INTO memberships(account_id,user_id,role,claims) VALUES($1,$2,'viewer',ARRAY['email:manage','documents:jobs:read'])`, f.otherAccount, f.owner.UserID); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	f.listener, err = pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = f.listener.Close(context.Background()) })
	if err = f.listener.QueryRow(t.Context(), `SELECT current_schema()`).Scan(&f.schema); err != nil {
		t.Fatal(err)
	}
	digest := md5.Sum([]byte(f.schema))
	f.channel = "domabas_rt_" + hex.EncodeToString(digest[:])
	if _, err = f.listener.Exec(t.Context(), "LISTEN "+pgx.Identifier{f.channel}.Sanitize()); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *independentRealtimeFixture) capture(t *testing.T, rollback bool, sql string, args ...any) []m.RealtimeSignal {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), 3*time.Second)
	defer cancel()
	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(context.Background()) }()
	if _, err = tx.Exec(ctx, sql, args...); err != nil {
		t.Fatal(err)
	}
	if rollback {
		err = tx.Rollback(ctx)
	} else {
		err = tx.Commit(ctx)
	}
	if err != nil {
		t.Fatal(err)
	}
	marker := uuid.NewString()
	if _, err = f.pool.Exec(ctx, `SELECT pg_notify($1,$2)`, f.channel, marker); err != nil {
		t.Fatal(err)
	}
	var signals []m.RealtimeSignal
	for {
		notification, err := f.listener.WaitForNotification(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if notification.Payload == marker {
			return signals
		}
		if notification.Channel != f.channel || len(notification.Payload) > 512 {
			t.Fatalf("invalid notification envelope: %+v", notification)
		}
		var payload map[string]any
		if err = json.Unmarshal([]byte(notification.Payload), &payload); err != nil {
			t.Fatal(err)
		}
		if payload["schema"] != f.schema || payload["version"] != float64(1) {
			t.Fatalf("wrong scope/version: %v", payload)
		}
		for key := range payload {
			if !slices.Contains([]string{"schema", "version", "kind", "account", "user"}, key) {
				t.Fatalf("private field %q in signal", key)
			}
		}
		value := func(key string) string {
			if v, ok := payload[key].(string); ok {
				return v
			}
			return ""
		}
		signals = append(signals, m.RealtimeSignal{Kind: value("kind"), AccountID: value("account"), UserID: value("user")})
	}
}

func (f *independentRealtimeFixture) wantTopics(t *testing.T, subject m.RealtimeSubject, signals []m.RealtimeSignal, want ...m.RealtimeTopic) {
	t.Helper()
	got, err := f.service.Authorize(t.Context(), subject, signals, false)
	slices.Sort(want)
	if err != nil || !slices.Equal(got, want) {
		t.Fatalf("subject=%s signals=%+v topics=%v err=%v want=%v", subject.UserID, signals, got, err, want)
	}
}

func TestThumbnailJobNotificationsFollowVisibleStateAndNamespace(t *testing.T) {
	f := newIndependentRealtimeFixture(t)
	job := uuid.NewString()
	signals := f.capture(t, false, `INSERT INTO document_thumbnail_jobs(id,account_id,document_id,source_sha256,renderer_revision,workflow_id) VALUES($1,$2,$3,repeat('a',64),1,$4)`, job, f.account, uuid.NewString(), "document-thumbnail-v1/"+job)
	if len(signals) != 1 || signals[0].Kind != "document_job" || signals[0].AccountID != f.account || signals[0].UserID != "" {
		t.Fatalf("thumbnail discovery attribution: %+v", signals)
	}
	f.wantTopics(t, f.owner, signals, m.Processing)
	f.wantTopics(t, f.peer, signals, m.Processing)
	f.wantTopics(t, f.outsider, signals)
	signals = f.capture(t, false, `UPDATE document_thumbnail_jobs SET lease_token=gen_random_uuid(),next_check_at=clock_timestamp() WHERE id=$1`, job)
	if len(signals) != 0 {
		t.Fatalf("scheduler housekeeping emitted visible changes: %+v", signals)
	}
	signals = f.capture(t, true, `UPDATE document_thumbnail_jobs SET status='running' WHERE id=$1`, job)
	if len(signals) != 0 {
		t.Fatalf("rolled-back render emitted a change: %+v", signals)
	}
	for _, status := range []string{"running", "failed"} {
		signals = f.capture(t, false, `UPDATE document_thumbnail_jobs SET status=$2 WHERE id=$1`, job, status)
		if len(signals) != 1 || signals[0].Kind != "document_job" {
			t.Fatalf("thumbnail outcome did not invalidate history: %+v", signals)
		}
		f.wantTopics(t, f.owner, signals, m.Processing)
		f.wantTopics(t, f.outsider, signals)
	}
}

func TestIndependentRealtimeTriggerAttributionAndFreshRecipientPolicy(t *testing.T) {
	f := newIndependentRealtimeFixture(t)
	job, document := uuid.NewString(), uuid.NewString()
	signals := f.capture(t, false, `INSERT INTO document_processing_jobs(id,account_id,document_id,generation,generation_sequence,requires_extraction,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,created_at,updated_at,initiated_by_user_id) VALUES($1,$2,$3,1,1,true,'upload',1,repeat('a',64),'{}','running','extract','machine',clock_timestamp(),clock_timestamp(),$4)`, job, f.account, document, f.owner.UserID)
	if len(signals) != 1 || signals[0].Kind != "document_job" || signals[0].UserID != f.owner.UserID {
		t.Fatalf("standalone attribution: %+v", signals)
	}
	f.wantTopics(t, f.owner, signals, m.Activity, m.Processing)
	f.wantTopics(t, f.peer, signals, m.Processing)
	f.wantTopics(t, f.outsider, signals)
	batch := uuid.NewString()
	signals = f.capture(t, false, `UPDATE document_processing_jobs SET parent_batch_id=$1,status='succeeded',finished_at=clock_timestamp() WHERE id=$2`, batch, job)
	f.wantTopics(t, f.owner, signals, m.Activity, m.Processing)
	signals = f.capture(t, false, `UPDATE document_processing_jobs SET status='superseded' WHERE id=$1`, job)
	if len(signals) != 1 || signals[0].UserID != "" {
		t.Fatalf("child activity attribution escaped: %+v", signals)
	}
	f.wantTopics(t, f.owner, signals, m.Processing)
	f.wantTopics(t, f.peer, signals, m.Processing)
	signals = f.capture(t, false, `INSERT INTO document_reindex_batches(id,account_id,requester_id,reason,configuration_revision,configuration_fingerprint,cutoff_sequence) VALUES($1,$2,$3,'manual',1,repeat('a',64),0)`, batch, f.account, f.owner.UserID)
	f.wantTopics(t, f.owner, signals, m.Activity, m.Processing)
	f.wantTopics(t, f.peer, signals, m.Processing)
	provider := uuid.NewString()
	signals = f.capture(t, false, `INSERT INTO email_providers(id,account_id,owner_id,label,host,port,mailbox,interval_minutes,max_age_days,page_size) VALUES($1,$2,$3,'Private label','mail.example.test',993,'INBOX',15,30,50)`, provider, f.account, f.owner.UserID)
	f.wantTopics(t, f.owner, signals, m.Activity, m.Email)
	f.wantTopics(t, f.peer, signals)
	f.wantTopics(t, f.manager, signals)
	f.wantTopics(t, f.outsider, signals)
	signals = f.capture(t, false, `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, f.otherAccount, f.owner.UserID)
	f.wantTopics(t, f.owner, signals, m.Activity, m.Identity)
	f.wantTopics(t, f.peer, signals)
	f.wantTopics(t, f.manager, signals)
	f.wantTopics(t, f.outsider, signals, m.Members)
	if _, err := f.service.Authorize(t.Context(), f.owner, nil, true); err != nil {
		t.Fatalf("unrelated library revocation ended valid session: %v", err)
	}
}

func TestIndependentRealtimeMemberProjectionAndSessionPrivacy(t *testing.T) {
	f := newIndependentRealtimeFixture(t)
	signals := f.capture(t, false, `UPDATE users SET must_change_password=true WHERE id=$1`, f.peer.UserID)
	f.wantTopics(t, f.manager, signals, m.Members)
	f.wantTopics(t, f.owner, signals)
	f.wantTopics(t, f.outsider, signals)
	for _, signal := range signals {
		if signal.Kind == "system_users" {
			t.Fatal("private password requirement broadcast as public system user activity")
		}
	}
	if _, err := f.service.Authorize(t.Context(), f.peer, nil, true); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("must-change session accepted: %v", err)
	}
	signals = f.capture(t, false, `UPDATE users SET email='outside-renamed@example.test' WHERE id=$1`, f.outsider.UserID)
	f.wantTopics(t, f.manager, signals)
	f.wantTopics(t, f.owner, signals)
	f.capture(t, false, `UPDATE users SET system_role='admin' WHERE id=$1`, f.manager.UserID)
	f.wantTopics(t, f.manager, signals, m.SystemUsers)
	signals = f.capture(t, false, `UPDATE users SET password_hash='new-private-hash' WHERE id=$1`, f.owner.UserID)
	if len(signals) != 0 {
		t.Fatalf("password-only signal: %+v", signals)
	}
	signals = f.capture(t, false, `INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES(repeat('e',64),$1,$2,1)`, f.account, f.owner.UserID)
	if len(signals) != 0 {
		t.Fatalf("login timing signal: %+v", signals)
	}
	signals = f.capture(t, false, `DELETE FROM sessions WHERE digest=repeat('e',64)`)
	f.wantTopics(t, f.owner, signals, m.Activity, m.Identity)
	f.wantTopics(t, f.manager, signals)
	signals = f.capture(t, false, `UPDATE users SET credential_revision=2 WHERE id=$1`, f.owner.UserID)
	if _, err := f.service.Authorize(t.Context(), f.owner, signals, false); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("stale credential session accepted: %v", err)
	}
	f.wantTopics(t, f.manager, signals)
}

func TestIndependentRealtimeCommitNoiseAndUnlockedSnapshot(t *testing.T) {
	f := newIndependentRealtimeFixture(t)
	document := uuid.NewString()
	f.capture(t, false, `INSERT INTO documents(id,account_id,title,created_at) VALUES($1,$2,'Original',clock_timestamp())`, document, f.account)
	signals := f.capture(t, true, `UPDATE documents SET title='Rolled back' WHERE id=$1`, document)
	if len(signals) != 0 {
		t.Fatalf("rollback emitted %+v", signals)
	}
	signals = f.capture(t, false, `UPDATE documents SET title=title WHERE id=$1`, document)
	if len(signals) != 0 {
		t.Fatalf("no-op emitted %+v", signals)
	}
	signals = f.capture(t, false, `UPDATE documents SET ocr_manual_text='Corrected search text',ocr_revision=ocr_revision+1 WHERE id=$1`, document)
	f.wantTopics(t, f.owner, signals, m.Documents, m.Processing, m.Activity)
	f.wantTopics(t, f.outsider, signals)
	provider := uuid.NewString()
	f.capture(t, false, `INSERT INTO email_providers(id,account_id,owner_id,label,host,port,mailbox,interval_minutes,max_age_days,page_size,credential_key_id,credential_ciphertext) VALUES($1,$2,$3,'Private','mail.example.test',993,'INBOX',15,30,50,'old',decode(repeat('ab',40),'hex'))`, provider, f.account, f.owner.UserID)
	signals = f.capture(t, false, `UPDATE email_providers SET credential_key_id='new',credential_ciphertext=decode(repeat('cd',40),'hex'),updated_at=clock_timestamp(),last_served_at=clock_timestamp(),next_poll_at=clock_timestamp()+interval '5 minutes' WHERE id=$1`, provider)
	if len(signals) != 0 {
		t.Fatalf("rewrap/reservation exposed timing %+v", signals)
	}
	tx, err := f.pool.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(context.Background()) }()
	if _, err = tx.Exec(t.Context(), `SELECT id FROM users WHERE id=$1 FOR UPDATE`, f.owner.UserID); err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec(t.Context(), `SELECT account_id FROM memberships WHERE user_id=$1 FOR UPDATE`, f.owner.UserID); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 300*time.Millisecond)
	defer cancel()
	if _, err = f.service.Authorize(ctx, f.owner, nil, true); err != nil {
		t.Fatalf("readonly authority snapshot blocked on row locks: %v", err)
	}
}
