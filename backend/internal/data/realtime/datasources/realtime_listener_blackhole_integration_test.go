//go:build integration

package datasources

import (
	"context"
	"net"
	"net/url"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	r "github.com/domabas/domabas/backend/internal/data/realtime/models"
	"github.com/domabas/domabas/backend/internal/testdb"
)

func TestListenerBlackholeBecomesUnreadyWhilePoolIsHealthy(t *testing.T) {
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
	parsed, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	target := parsed.Host
	proxy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer proxy.Close()
	var blackhole atomic.Bool
	var workers sync.WaitGroup
	var lock sync.Mutex
	var sockets []net.Conn
	workers.Add(1)
	go func() {
		defer workers.Done()
		for {
			client, err := proxy.Accept()
			if err != nil {
				return
			}
			upstream, err := net.DialTimeout("tcp", target, time.Second)
			if err != nil {
				_ = client.Close()
				continue
			}
			lock.Lock()
			sockets = append(sockets, client, upstream)
			lock.Unlock()
			for _, pair := range [][2]net.Conn{{client, upstream}, {upstream, client}} {
				workers.Add(1)
				go func() {
					defer workers.Done()
					buffer := make([]byte, 32768)
					for {
						n, err := pair[0].Read(buffer)
						if err != nil {
							return
						}
						if blackhole.Load() {
							continue
						}
						if _, err = pair[1].Write(buffer[:n]); err != nil {
							return
						}
					}
				}()
			}
		}
	}()
	defer func() {
		_ = proxy.Close()
		lock.Lock()
		for _, socket := range sockets {
			_ = socket.Close()
		}
		lock.Unlock()
		workers.Wait()
	}()
	parsed.Host = proxy.Addr().String()
	listener, err := NewRealtimeNotificationDataSource(parsed.String())
	if err != nil {
		t.Fatal(err)
	}
	sink := &sinkStub{health: make(chan bool, 8), signals: make(chan r.RealtimeSignal, 8)}
	if err = listener.Start(ctx, sink); err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	if healthy := <-sink.health; !healthy {
		t.Fatal("listener never became healthy")
	}
	blackhole.Store(true)
	probe, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if err = source.Ping(probe); err != nil {
		t.Fatal(err)
	}
	select {
	case healthy := <-sink.health:
		if healthy {
			t.Fatal("unexpected healthy transition")
		}
	case <-time.After(13 * time.Second):
		t.Fatal("blackholed listener remained healthy beyond 12s plus scheduling allowance")
	}
	if err = source.Ping(ctx); err != nil {
		t.Fatal("ordinary pool failed during dedicated listener blackhole", err)
	}
}
