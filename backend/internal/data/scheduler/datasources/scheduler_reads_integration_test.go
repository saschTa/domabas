//go:build integration

package datasources

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	identitycontainer "github.com/domabas/domabas/backend/internal/bootstrap/identity"
	schedulerrepos "github.com/domabas/domabas/backend/internal/data/scheduler/repos"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	p "github.com/domabas/domabas/backend/internal/domain/scheduler/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	schedulerservices "github.com/domabas/domabas/backend/internal/domain/scheduler/services"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func schedulerSettingsActor(t *testing.T, f *schedulerAdmissionFixture) m.SchedulerActor {
	t.Helper()
	identities, err := identitycontainer.NewIdentityContainer(f.database.Database(), time.Now)
	if err != nil {
		t.Fatal(err)
	}
	f.service = schedulerservices.NewSchedulerService(schedulerrepos.NewSchedulerRepository(f.source), identities.Service())
	a := m.SchedulerActor{AccountID: uuid.NewString(), UserID: uuid.NewString(), SessionDigest: strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", ""), CredentialRevision: 1}
	f.exec("BEGIN")
	f.exec(`INSERT INTO accounts(id,name) VALUES($1,'Scheduler read tests')`, a.AccountID)
	f.exec(`INSERT INTO users(id,email,password_hash,personal_account_id,system_role) VALUES($1,$2,'unused',$3,'admin')`, a.UserID, a.UserID+"@example.test", a.AccountID)
	f.exec(`INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)`, a.AccountID, a.UserID)
	f.exec(`INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)`, a.SessionDigest, a.AccountID, a.UserID)
	f.exec("COMMIT")
	return a
}

func TestSchedulerSettingsReadIgnoresAuthorityAndSchedulerLocks(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	blocker, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	for _, query := range []string{
		"SELECT id FROM accounts FOR UPDATE", "SELECT id FROM users FOR UPDATE",
		"SELECT user_id FROM memberships FOR UPDATE", "SELECT digest FROM sessions FOR UPDATE",
		"SELECT singleton FROM scheduler_settings FOR UPDATE", "SELECT id FROM scheduler_resources FOR UPDATE",
		"SELECT singleton FROM chat_configuration FOR UPDATE", "SELECT id FROM document_processing_configuration FOR UPDATE",
	} {
		if _, err := blocker.Exec(t.Context(), query); err != nil {
			t.Fatal(err)
		}
	}
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	if _, err := f.service.Settings(ctx, actor); err != nil {
		t.Fatalf("read waited for held authority/scheduler locks: %v", err)
	}
}

func TestSchedulerSettingsWriteDoesNotLockAuthorityRows(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	settings, err := f.service.Settings(t.Context(), actor)
	if err != nil {
		t.Fatal(err)
	}
	blocker, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	for _, query := range []string{
		"SELECT id FROM accounts FOR UPDATE", "SELECT id FROM users FOR UPDATE",
		"SELECT user_id FROM memberships FOR UPDATE", "SELECT digest FROM sessions FOR UPDATE",
	} {
		if _, err := blocker.Exec(t.Context(), query); err != nil {
			t.Fatal(err)
		}
	}
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	saved, err := f.service.UpdateSettings(ctx, actor, m.SchedulerSettingsUpdate{ExpectedRevision: settings.Revision, Resources: []m.SchedulerResourceUpdate{{ID: "worker", Limit: 12}}})
	if err != nil || saved.Resources[0].Limit != 12 {
		t.Fatalf("settings write waited for authority locks: %+v %v", saved, err)
	}
}

func TestSchedulerSettingsProjectsNewProviderWithoutWrites(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	before, err := f.service.Settings(t.Context(), actor)
	if err != nil {
		t.Fatal(err)
	}
	f.exec(`UPDATE chat_configuration SET provider='openai',base_url='https://PROVIDER.example.test:443/v1'`)
	f.exec(`UPDATE document_processing_configuration SET scheduler_provider='openai',scheduler_base_url='https://provider.example.test/other'`)
	id := f.source.ResourceID("https://provider.example.test")
	projected, err := f.service.Settings(t.Context(), actor)
	if err != nil || projected.Revision != before.Revision || len(projected.Resources) != 3 {
		t.Fatalf("provider projection: %+v %v", projected, err)
	}
	index := slices.IndexFunc(projected.Resources, func(v m.SchedulerResource) bool { return v.ID == id })
	if index < 0 || projected.Resources[index].Label != "https://provider.example.test" || projected.Resources[index].Limit != 2 {
		t.Fatalf("provider defaults: %+v", projected.Resources)
	}
	for _, pipeline := range projected.Pipelines {
		if (pipeline.ID == "document_ai" || pipeline.ID == "chat") && !slices.Contains(pipeline.ResourceIDs, id) {
			t.Fatalf("provider not shared by pipelines: %+v", projected.Pipelines)
		}
	}
	var count int
	if err := f.connection.QueryRow(t.Context(), "SELECT count(*) FROM scheduler_resources").Scan(&count); err != nil || count != 2 {
		t.Fatalf("GET wrote provider resources: %d %v", count, err)
	}
	update := m.SchedulerSettingsUpdate{ExpectedRevision: projected.Revision, Resources: []m.SchedulerResourceUpdate{{ID: id, Limit: 7}}}
	saved, err := f.service.UpdateSettings(t.Context(), actor, update)
	if err != nil || saved.Revision <= projected.Revision {
		t.Fatalf("save manufactured a conflict: %+v %v", saved, err)
	}
	index = slices.IndexFunc(saved.Resources, func(v m.SchedulerResource) bool { return v.ID == id })
	if index < 0 || saved.Resources[index].Limit != 7 {
		t.Fatalf("projected resource limit not saved: %+v", saved.Resources)
	}
	if _, err := f.service.UpdateSettings(t.Context(), actor, update); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("stale revision accepted: %v", err)
	}
}

func TestSchedulerSettingsRejectsVanishedProjectionAndCapacityOverflow(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	f.exec(`UPDATE chat_configuration SET provider='openai',base_url='https://temporary.example.test/v1'`)
	projected, err := f.service.Settings(t.Context(), actor)
	if err != nil {
		t.Fatal(err)
	}
	id := f.source.ResourceID("https://temporary.example.test")
	f.exec(`UPDATE chat_configuration SET provider='ollama',base_url=''`)
	update := m.SchedulerSettingsUpdate{ExpectedRevision: projected.Revision, Resources: []m.SchedulerResourceUpdate{{ID: id, Limit: 7}}}
	var invalid m.SchedulerValidationError
	if _, err := f.service.UpdateSettings(t.Context(), actor, update); !errors.As(err, &invalid) {
		t.Fatalf("vanished provider materialized: %v", err)
	}
	for i := range 254 {
		origin := fmt.Sprintf("https://provider-%d.example.test", i)
		f.exec(`INSERT INTO scheduler_resources(id,label,origin,concurrency_limit) VALUES($1,$2,$2,2)`, f.source.ResourceID(origin), origin)
	}
	f.exec(`UPDATE chat_configuration SET provider='openai',base_url='https://temporary.example.test/v1'`)
	if _, err := f.service.UpdateSettings(t.Context(), actor, update); !errors.As(err, &invalid) {
		t.Fatalf("resource capacity exceeded: %v", err)
	}
	var count int
	var revision int64
	if err := f.connection.QueryRow(t.Context(), "SELECT revision,(SELECT count(*) FROM scheduler_resources) FROM scheduler_settings").Scan(&revision, &count); err != nil || count != 256 || revision != projected.Revision {
		t.Fatalf("invalid save committed partial state: revision %d resources %d %v", revision, count, err)
	}
}

func TestSchedulerSettingsExcludesOnlyKnownClosedExecutionsWithoutReconciling(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	for _, pipeline := range []string{"document_ingestion", "document_ai", "email", "paperless", "chat"} {
		for _, state := range []string{"closed", "open", "missing"} {
			id := uuid.NewString()
			workflow := pipeline + "-" + id
			closed := state == "closed"
			if pipeline == "paperless" {
				workflow = "domabas-paperless-" + id
			}
			if state != "missing" {
				switch pipeline {
				case "document_ingestion":
					f.exec(`INSERT INTO document_processing_executions(account_id,document_id,generation,workflow_id,admitted_at,delivery_deadline,closed_at) VALUES($1,$2,1,$3,clock_timestamp(),clock_timestamp()+interval '1 hour',CASE WHEN $4 THEN clock_timestamp() END)`, actor.AccountID, id, workflow, closed)
				case "document_ai":
					f.exec(`INSERT INTO document_ai_jobs(account_id,document_id,generation,attempt,ocr_revision,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,workflow_id,closed_at) VALUES($1,$2,1,1,0,'upload',1,'test','{}','succeeded','complete','machine',$3,CASE WHEN $4 THEN clock_timestamp() END)`, actor.AccountID, id, workflow, closed)
				case "email":
					f.exec(`INSERT INTO email_executions(run_id,workflow_id,task_queue,first_attempt_at,start_window_end,closed_at) VALUES($1,$2,'test',transaction_timestamp(),transaction_timestamp()+interval '23 hours 59 minutes',CASE WHEN $3 THEN clock_timestamp() END)`, id, workflow, closed)
				case "paperless":
					f.exec(`INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,task_queue,state,execution_closed) VALUES($1,$2,$3,1,'https://paperless.example.test','test','test','succeeded',$4)`, id, actor.AccountID, actor.UserID, closed)
				case "chat":
					f.exec(`INSERT INTO chat_conversations(id,account_id,owner_id,request_id) VALUES($1,$2,$3,$1)`, id, actor.AccountID, actor.UserID)
					f.exec(`INSERT INTO chat_turns(id,conversation_id,account_id,owner_id,request_id,credential_revision,content_hash,configuration_revision,provider,model,base_url,internal_runtime,workflow_id,task_queue,status,execution_closed) VALUES($1,$1,$2,$3,$1,1,'test',1,'ollama','test','',true,$4,'test','completed',$5)`, id, actor.AccountID, actor.UserID, workflow, closed)
				}
			}
			f.exec(`INSERT INTO scheduler_requests(workflow_id,pipeline,state) VALUES($1,$2,'active')`, workflow, pipeline)
			f.exec(`INSERT INTO scheduler_request_resources(workflow_id,resource_id) VALUES($1,'worker')`, workflow)
		}
	}
	settings, err := f.service.Settings(t.Context(), actor)
	if err != nil || settings.Resources[0].ActiveJobs != 10 {
		t.Fatalf("closed/open/unverifiable projection: %+v %v", settings, err)
	}
	if count := f.active("worker"); count != 15 {
		t.Fatalf("GET reconciled stored requests: %d", count)
	}
	saved, err := f.service.UpdateSettings(t.Context(), actor, m.SchedulerSettingsUpdate{ExpectedRevision: settings.Revision, Resources: []m.SchedulerResourceUpdate{{ID: "worker", Limit: settings.Resources[0].Limit}}})
	if err != nil {
		t.Fatal(err)
	}
	if saved.Resources[0].ActiveJobs != 10 || f.active("worker") != 15 {
		t.Fatalf("settings save reconciled ownership or returned stale counts: %+v", saved)
	}
	if err := pgx.BeginFunc(t.Context(), f.database.Database(), func(tx pgx.Tx) error {
		if err := schedulerLock(t.Context(), tx); err != nil {
			return err
		}
		return prepareSchedulerAdmission(t.Context(), tx)
	}); err != nil {
		t.Fatal(err)
	}
	if count := f.active("worker"); count != 10 {
		t.Fatalf("read projection differs from mutation reconciliation: %d", count)
	}
}

type schedulerPausedPolicy struct {
	delegate p.SchedulerAuthority
	entered  chan struct{}
	release  chan struct{}
}

func (p schedulerPausedPolicy) ResolveAuthority(ctx context.Context, actor i.IdentityPrincipal) (i.IdentityPrincipal, error) {
	principal, err := p.delegate.ResolveAuthority(ctx, actor)
	if err != nil {
		return principal, err
	}
	close(p.entered)
	<-p.release
	return principal, nil
}

func TestSchedulerReadDoesNotDelaySessionRevocation(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	identities, err := identitycontainer.NewIdentityContainer(f.database.Database(), time.Now)
	if err != nil {
		t.Fatal(err)
	}
	policy := schedulerPausedPolicy{delegate: identities.Service(), entered: make(chan struct{}), release: make(chan struct{})}
	f.service = schedulerservices.NewSchedulerService(schedulerrepos.NewSchedulerRepository(f.source), policy)
	done := make(chan error, 1)
	go func() { _, err := f.service.Settings(t.Context(), actor); done <- err }()
	select {
	case <-policy.entered:
	case <-time.After(2 * time.Second):
		t.Fatal("read never reached authority evaluation")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	_, revokeErr := f.connection.Exec(ctx, "DELETE FROM sessions WHERE digest=$1", actor.SessionDigest)
	close(policy.release)
	if err := <-done; err != nil {
		t.Fatalf("already authorized snapshot failed: %v", err)
	}
	if revokeErr != nil {
		t.Fatalf("read delayed session revocation: %v", revokeErr)
	}
	f.service = schedulerservices.NewSchedulerService(schedulerrepos.NewSchedulerRepository(f.source), policy.delegate)
	if _, err := f.service.Settings(t.Context(), actor); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("new request accepted revoked session: %v", err)
	}
}
