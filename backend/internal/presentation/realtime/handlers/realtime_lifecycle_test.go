package handlers

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

type upgradeProbe struct {
	*httptest.ResponseRecorder
	read, write   bool
	panicDeadline bool
	connection    net.Conn
}

func (w *upgradeProbe) SetReadDeadline(time.Time) error {
	if w.panicDeadline {
		panic("test preupgrade panic")
	}
	w.read = true
	return nil
}
func (w *upgradeProbe) SetWriteDeadline(time.Time) error { w.write = true; return nil }
func (w *upgradeProbe) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	if !w.read || !w.write {
		panic("deadlines not installed before flush")
	}
	return w.connection, bufio.NewReadWriter(bufio.NewReader(bytes.NewReader(nil)), bufio.NewWriter(io.Discard)), nil
}

type brokenCleanupConnection struct {
	net.Conn
	closed atomic.Int64
}

func (c *brokenCleanupConnection) SetDeadline(time.Time) error {
	return errors.New("test reset failure")
}
func (c *brokenCleanupConnection) Close() error { c.closed.Add(1); panic("test cleanup panic") }
func validRequest() *http.Request {
	r := httptest.NewRequest("GET", "http://example.test/api/v1/realtime", nil)
	for key, value := range map[string]string{"Connection": "Upgrade", "Upgrade": "websocket", "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": "AAAAAAAAAAAAAAAAAAAAAA==", "Sec-WebSocket-Protocol": "domabas.realtime.v1"} {
		r.Header.Set(key, value)
	}
	return r
}
func TestUpgradeDeadlineAndCleanupPanicRelease(t *testing.T) {
	s := NewRealtimeSupervisor(&testService{}, nil)
	s.SetHealthy(true)
	defer s.Close()
	broken := &brokenCleanupConnection{}
	w := &upgradeProbe{ResponseRecorder: httptest.NewRecorder(), connection: broken}
	if err := (realtimeStreamResponse{s, validRequest()}).VisitOpenRealtimeResponse(w); err != nil {
		t.Fatal(err)
	}
	if w.Code != 101 || broken.closed.Load() == 0 {
		t.Fatalf("status=%d close=%d", w.Code, broken.closed.Load())
	}
	s.mu.Lock()
	active, pending := len(s.clients), s.pending
	s.mu.Unlock()
	if active != 0 || pending != 0 {
		t.Fatalf("leaked admission: %d %d", active, pending)
	}
	pre := &upgradeProbe{ResponseRecorder: httptest.NewRecorder(), panicDeadline: true}
	_ = (realtimeStreamResponse{s, validRequest()}).VisitOpenRealtimeResponse(pre)
	if pre.Code != 503 {
		t.Fatalf("preupgrade panic status=%d", pre.Code)
	}
}
func TestAdmissionAndEstablishedCheckCapacity(t *testing.T) {
	s := NewRealtimeSupervisor(&testService{}, nil)
	s.SetHealthy(true)
	defer s.Close()
	for range 16 {
		c, status := s.reserve()
		if status != 0 {
			t.Fatal(status)
		}
		s.release(c)
	}
	if _, status := s.reserve(); status != 429 {
		t.Fatalf("rapid attempts escaped bucket: %d", status)
	}
	s.initial <- struct{}{}
	defer func() { <-s.initial }()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	var ran atomic.Bool
	if !s.checks.do(ctx, true, func() { ran.Store(true) }) || !ran.Load() {
		t.Fatal("new authentication starved live authorization")
	}
}
func TestRejectedHandshakesConsumeGlobalAdmission(t *testing.T) {
	s := NewRealtimeSupervisor(&testService{}, nil)
	s.SetHealthy(true)
	defer s.Close()
	for i := 0; i < 17; i++ {
		r := validRequest()
		r.Header.Del("Sec-WebSocket-Protocol")
		w := httptest.NewRecorder()
		_ = (realtimeStreamResponse{s, r}).VisitOpenRealtimeResponse(w)
		want := 400
		if i == 16 {
			want = 429
		}
		if w.Code != want {
			t.Fatalf("attempt %d status=%d want %d", i, w.Code, want)
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.clients) != 0 || s.pending != 0 {
		t.Fatal("rejected handshake leaked capacity")
	}
}
