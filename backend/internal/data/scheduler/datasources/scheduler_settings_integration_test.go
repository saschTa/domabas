//go:build integration

package datasources

import (
	"context"
	"errors"
	"strings"
	"testing"

	identitycontainer "github.com/domabas/domabas/backend/internal/bootstrap/identity"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulerrepos "github.com/domabas/domabas/backend/internal/data/scheduler/repos"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	schedulerservices "github.com/domabas/domabas/backend/internal/domain/scheduler/services"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"time"
)

func TestSchedulerSettingsAuthorityRevisionAndLimits(t *testing.T) {
	url := testdb.New(t)
	database, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(database.Close)
	if err = database.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { connection.Close(context.Background()) })
	exec := func(query string, args ...any) {
		t.Helper()
		if _, err := connection.Exec(t.Context(), query, args...); err != nil {
			t.Fatal(err)
		}
	}
	identities, err := identitycontainer.NewIdentityContainer(database.Database(), time.Now)
	if err != nil {
		t.Fatal(err)
	}
	source := NewSchedulerDataSource(database.Database(), 16, "http://ollama.test:11434")
	if err = source.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	service := schedulerservices.NewSchedulerService(schedulerrepos.NewSchedulerRepository(source), identities.Service())
	actor := m.SchedulerActor{AccountID: uuid.NewString(), UserID: uuid.NewString(), SessionDigest: strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", ""), CredentialRevision: 1}
	exec("BEGIN")
	exec(`INSERT INTO accounts(id,name) VALUES($1,'Scheduler settings')`, actor.AccountID)
	exec(`INSERT INTO users(id,email,password_hash,personal_account_id,system_role) VALUES($1,$2,'unused',$3,'admin')`, actor.UserID, actor.UserID+"@example.test", actor.AccountID)
	exec(`INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)`, actor.AccountID, actor.UserID)
	exec(`INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)`, actor.SessionDigest, actor.AccountID, actor.UserID)
	exec("COMMIT")
	settings, err := service.Settings(t.Context(), actor)
	if err != nil {
		t.Fatal(err)
	}
	if settings.OllamaQueueSize != 16 || len(settings.Pipelines) != 6 || len(settings.Resources) != 2 {
		t.Fatalf("settings %+v", settings)
	}
	update := m.SchedulerSettingsUpdate{ExpectedRevision: settings.Revision, Resources: []m.SchedulerResourceUpdate{{ID: "worker", Limit: 12}, {ID: "ollama", Limit: 8}}}
	saved, err := service.UpdateSettings(t.Context(), actor, update)
	if err != nil || saved.Revision != settings.Revision+1 {
		t.Fatal(saved, err)
	}
	if _, err = service.UpdateSettings(t.Context(), actor, update); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("stale revision: %v", err)
	}
	update.ExpectedRevision = saved.Revision
	update.Resources = []m.SchedulerResourceUpdate{{ID: "worker", Limit: 1}, {ID: "ollama", Limit: 9}}
	var invalid m.SchedulerValidationError
	if _, err = service.UpdateSettings(t.Context(), actor, update); !errors.As(err, &invalid) {
		t.Fatalf("queue overflow: %v", err)
	}
	current, err := service.Settings(t.Context(), actor)
	if err != nil || current.Revision != saved.Revision || current.Resources[0].Limit != 12 {
		t.Fatal("partial invalid update committed", current, err)
	}
	exec(`UPDATE users SET system_role='user' WHERE id=$1`, actor.UserID)
	if _, err = service.Settings(t.Context(), actor); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("namespace owner read system workload: %v", err)
	}
	exec(`UPDATE users SET system_role='admin' WHERE id=$1`, actor.UserID)
	exec(`DELETE FROM sessions WHERE digest=$1`, actor.SessionDigest)
	if _, err = service.Settings(t.Context(), actor); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("revoked session read settings: %v", err)
	}
}
