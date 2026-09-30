package handlers

import (
	"context"
	"sync"
	"time"

	"github.com/coder/websocket"
	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
)

type RealtimeService interface {
	Authenticate(context.Context, string) (m.RealtimeSubject, error)
	Authorize(context.Context, m.RealtimeSubject, []m.RealtimeSignal, bool) ([]m.RealtimeTopic, error)
}
type RealtimeSupervisor struct {
	service           RealtimeService
	ctx               context.Context
	cancel            context.CancelFunc
	mu                sync.Mutex
	healthy, draining bool
	epoch             uint64
	clients           map[*realtimeConnection]bool
	users             map[string]int
	pending           int
	tokens            float64
	lastToken         time.Time
	initial           chan struct{}
	checks            *realtimeCheckScheduler
	ingress           chan m.RealtimeSignal
	overflow          chan struct{}
	wg                sync.WaitGroup
	closeOnce         sync.Once
	origins           []string
	phase             uint64
}
type realtimeConnection struct {
	supervisor      *RealtimeSupervisor
	ctx             context.Context
	cancel          context.CancelFunc
	socket          *websocket.Conn
	subject         m.RealtimeSubject
	epoch           uint64
	mu              sync.Mutex
	candidates      map[m.RealtimeSignal]bool
	resync          bool
	wake            chan struct{}
	closeCode       int
	heartbeatOffset time.Duration
}
type realtimeCheckRequest struct {
	ctx      context.Context
	run      func()
	done     chan struct{}
	priority bool
}
type realtimeCheckScheduler struct {
	requests chan *realtimeCheckRequest
	stop     chan struct{}
	done     chan struct{}
}
