package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
)

type testService struct {
	revoked atomic.Bool
	calls   atomic.Int64
}

func (s *testService) Authenticate(context.Context, string) (m.RealtimeSubject, error) {
	return m.RealtimeSubject{UserID: "user", AccountID: "account"}, nil
}
func (s *testService) Authorize(_ context.Context, _ m.RealtimeSubject, signals []m.RealtimeSignal, resync bool) ([]m.RealtimeTopic, error) {
	s.calls.Add(1)
	if s.revoked.Load() {
		return nil, m.ErrUnauthorized
	}
	if resync {
		return []m.RealtimeTopic{m.Documents, m.Identity}, nil
	}
	if len(signals) > 0 {
		return []m.RealtimeTopic{m.Documents}, nil
	}
	return nil, nil
}
func testSocket(t *testing.T, s *RealtimeSupervisor) (*websocket.Conn, *httptest.Server) {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = (realtimeStreamResponse{s, r}).VisitOpenRealtimeResponse(w)
	}))
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(server.URL, "http"), &websocket.DialOptions{Subprotocols: []string{"domabas.realtime.v1"}})
	if err != nil {
		server.Close()
		t.Fatal(err)
	}
	if err = conn.Write(ctx, websocket.MessageText, []byte(`{"type":"authenticate","version":1,"token":"`+strings.Repeat("A", 43)+`"}`)); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.CloseNow(); server.Close() })
	return conn, server
}
func readType(t *testing.T, c *websocket.Conn, kind string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	for {
		_, body, err := c.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var v struct {
			Type   string   `json:"type"`
			Topics []string `json:"topics"`
		}
		if json.Unmarshal(body, &v) != nil {
			t.Fatal(string(body))
		}
		if v.Type == kind {
			return
		}
	}
}
func TestReadyInvalidationRevocationAndDrain(t *testing.T) {
	service := &testService{}
	s := NewRealtimeSupervisor(service, nil)
	s.SetHealthy(true)
	defer s.Close()
	c, _ := testSocket(t, s)
	readType(t, c, "ready")
	s.Publish(m.RealtimeSignal{Kind: "documents", AccountID: "account"})
	readType(t, c, "invalidate")
	service.revoked.Store(true)
	s.Publish(m.RealtimeSignal{Kind: "authority", UserID: "user"})
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	for {
		_, _, err := c.Read(ctx)
		if err != nil {
			if websocket.CloseStatus(err) != 4401 {
				t.Fatalf("close=%v", err)
			}
			break
		}
	}
	start := time.Now()
	s.Close()
	if time.Since(start) > 2*time.Second {
		t.Fatal("drain was not bounded")
	}
}
func TestListenerLossAndCandidateSwap(t *testing.T) {
	s := NewRealtimeSupervisor(&testService{}, nil)
	s.SetHealthy(true)
	defer s.Close()
	c, _ := testSocket(t, s)
	readType(t, c, "ready")
	s.SetHealthy(false)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	for {
		_, _, err := c.Read(ctx)
		if err != nil {
			if websocket.CloseStatus(err) != 1013 {
				t.Fatal(err)
			}
			break
		}
	}
	probe := &realtimeConnection{candidates: map[m.RealtimeSignal]bool{}, wake: make(chan struct{}, 1)}
	probe.invalidate(m.RealtimeSignal{Kind: "documents", AccountID: "old"}, false)
	first, resync := probe.batch()
	probe.invalidate(m.RealtimeSignal{Kind: "documents", AccountID: "new"}, false)
	next, _ := probe.batch()
	if resync || len(first) != 1 || len(next) != 1 || first[0].AccountID != "old" || next[0].AccountID != "new" {
		t.Fatal("lost concurrent pending set")
	}
}
func TestOriginAndHandshakePolicy(t *testing.T) {
	r := httptest.NewRequest("GET", "http://example.test/api/v1/realtime", nil)
	r.Header.Set("Connection", "Upgrade")
	r.Header.Set("Upgrade", "websocket")
	r.Header.Set("Sec-WebSocket-Version", "13")
	r.Header.Set("Sec-WebSocket-Key", "AAAAAAAAAAAAAAAAAAAAAA==")
	r.Header.Set("Sec-WebSocket-Protocol", "domabas.realtime.v1")
	if got := validateHandshake(r, nil); got != 0 {
		t.Fatal(got)
	}
	r.Header.Set("Origin", "http://example.test:80")
	if got := validateHandshake(r, nil); got != 0 {
		t.Fatal(got)
	}
	for _, origin := range []string{"null", "http://example.test/", "http://example.test?", "http://example.test#", "https://example.test", "http://evil.test"} {
		r.Header.Set("Origin", origin)
		if validateHandshake(r, nil) != 403 {
			t.Fatal(origin)
		}
	}
	r.Header.Set("Origin", "https://example.test")
	if validateHandshake(r, []string{"https://example.test:443"}) != 0 {
		t.Fatal("configured TLS origin rejected")
	}
}
