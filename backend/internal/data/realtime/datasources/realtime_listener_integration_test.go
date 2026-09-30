//go:build integration

package datasources

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"net/url"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	r "github.com/domabas/domabas/backend/internal/data/realtime/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type sinkStub struct {
	health  chan bool
	signals chan r.RealtimeSignal
}

func (s *sinkStub) Health(v bool)             { s.health <- v }
func (s *sinkStub) Notify(v r.RealtimeSignal) { s.signals <- v }
func TestListenerQuietProbeReconnectAndSchemaIsolation(t *testing.T) {
	databaseURL := testdb.New(t)
	ctx := t.Context()
	source, err := postgres.NewPostgresDataSource(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	if err = source.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	conn, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(context.Background())
	var schema string
	if err = conn.QueryRow(ctx, "SELECT current_schema()").Scan(&schema); err != nil {
		t.Fatal(err)
	}
	parsed, _ := url.Parse(databaseURL)
	q := parsed.Query()
	name := "realtime-test-" + uuid.NewString()
	q.Set("application_name", name)
	parsed.RawQuery = q.Encode()
	listener, err := NewRealtimeNotificationDataSource(parsed.String())
	if err != nil {
		t.Fatal(err)
	}
	sink := &sinkStub{health: make(chan bool, 8), signals: make(chan r.RealtimeSignal, 8)}
	if err = listener.Start(ctx, sink); err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	waitHealth := func(want bool) {
		t.Helper()
		select {
		case got := <-sink.health:
			if got != want {
				t.Fatalf("health=%v want %v", got, want)
			}
		case <-time.After(4 * time.Second):
			t.Fatal("listener health timeout")
		}
	}
	waitHealth(true)
	digest := md5.Sum([]byte(schema))
	channel := "domabas_rt_" + hex.EncodeToString(digest[:])
	send := func(namespace string) {
		t.Helper()
		body, _ := json.Marshal(r.RealtimeSignal{Version: 1, Schema: namespace, Kind: "configuration"})
		if _, err = conn.Exec(ctx, "SELECT pg_notify($1,$2)", channel, string(body)); err != nil {
			t.Fatal(err)
		}
	}
	send("foreign_schema")
	select {
	case <-sink.signals:
		t.Fatal("foreign schema accepted")
	case <-time.After(80 * time.Millisecond):
	}
	select {
	case got := <-sink.health:
		t.Fatalf("quiet wait caused unhealthy transition: %v", got)
	case <-time.After(11 * time.Second):
	}
	send(schema)
	select {
	case <-sink.signals:
	case <-time.After(time.Second):
		t.Fatal("notification missing after idle wait/probe")
	}
	var stopped bool
	if err = conn.QueryRow(ctx, "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name=$1", name).Scan(&stopped); err != nil || !stopped {
		t.Fatalf("stop listener=%v %v", stopped, err)
	}
	waitHealth(false)
	waitHealth(true)
	send(schema)
	select {
	case <-sink.signals:
	case <-time.After(time.Second):
		t.Fatal("notification missing after reconnect")
	}
	start := time.Now()
	listener.Close()
	if time.Since(start) > 2*time.Second {
		t.Fatal("listener cancellation was unbounded")
	}
	waitHealth(false)
}
