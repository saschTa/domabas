package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"time"

	"github.com/coder/websocket"
	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	wire "github.com/domabas/domabas/backend/internal/presentation/realtime/models"
)

func (c *realtimeConnection) serve(raw net.Conn) {
	var readerCancel context.CancelFunc
	var pingDone chan struct{}
	defer func() {
		if recover() != nil {
			c.setCode(1013)
		}
		c.cancel()
		c.mu.Lock()
		code := c.closeCode
		c.mu.Unlock()
		done := make(chan struct{})
		go func() { defer close(done); _ = c.socket.Close(websocket.StatusCode(code), closeReason(code)) }()
		timer := time.NewTimer(time.Second)
		select {
		case <-done:
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
		case <-timer.C:
			_ = raw.Close()
			<-done
		}
		if readerCancel != nil {
			readerCancel()
		}
		_ = c.socket.CloseNow()
		if pingDone != nil {
			<-pingDone
		}
	}()
	c.socket.SetReadLimit(1024)
	authCtx, authCancel := context.WithTimeout(c.ctx, 5*time.Second)
	defer authCancel()
	kind, body, err := c.socket.Read(authCtx)
	if err != nil {
		c.setCode(1008)
		return
	}
	if kind != websocket.MessageText {
		c.setCode(1008)
		return
	}
	token, err := wire.Authentication(body)
	if err != nil {
		c.setCode(1008)
		return
	}
	check, cancel := context.WithTimeout(authCtx, 2*time.Second)
	select {
	case c.supervisor.initial <- struct{}{}:
	case <-check.Done():
		cancel()
		c.setCode(1013)
		return
	}
	topics, err := c.initialize(check, token)
	token = ""
	body = nil
	cancel()
	authCancel()
	if err != nil {
		c.setCode(errorCode(err))
		return
	}
	readCtx, cancelReader := context.WithCancel(context.Background())
	readerCancel = cancelReader
	closed := c.socket.CloseRead(readCtx)
	pingDone = make(chan struct{})
	go c.pings(pingDone)
	if c.send("ready", topics) != nil {
		return
	}
	heartbeat := time.NewTimer(c.heartbeatOffset)
	defer heartbeat.Stop()
	var dirty *time.Timer
	var dirtyC <-chan time.Time
	defer func() {
		if dirty != nil {
			dirty.Stop()
		}
	}()
	for {
		select {
		case <-c.ctx.Done():
			return
		case <-closed.Done():
			return
		case <-c.wake:
			if dirty == nil {
				dirty = time.NewTimer(250 * time.Millisecond)
				dirtyC = dirty.C
			}
		case <-dirtyC:
			dirty = nil
			dirtyC = nil
			signals, resync := c.batch()
			priority := false
			for _, signal := range signals {
				if signal.Kind == "authority" {
					priority = true
				}
			}
			topics, err := c.authorize(signals, resync, priority)
			if err != nil {
				c.setCode(errorCode(err))
				return
			}
			frame := "invalidate"
			if resync {
				frame = "resync"
			}
			if len(topics) > 0 {
				if c.send(frame, topics) != nil {
					return
				}
			}
		case <-heartbeat.C:
			if _, err := c.authorize(nil, false, true); err != nil {
				c.setCode(errorCode(err))
				return
			}
			if c.send("heartbeat", nil) != nil {
				return
			}
			heartbeat.Reset(20 * time.Second)
		}
	}
}
func (c *realtimeConnection) initialize(ctx context.Context, token string) ([]m.RealtimeTopic, error) {
	defer func() { <-c.supervisor.initial }()
	subject, err := c.supervisor.service.Authenticate(ctx, token)
	if err != nil {
		return nil, err
	}
	if !c.supervisor.authenticate(c, subject) {
		return nil, m.ErrUnavailable
	}
	topics, err := c.supervisor.service.Authorize(ctx, subject, nil, true)
	if ctx.Err() != nil {
		return nil, m.ErrUnavailable
	}
	return topics, err
}
func (c *realtimeConnection) authorize(signals []m.RealtimeSignal, resync, priority bool) ([]m.RealtimeTopic, error) {
	ctx, cancel := context.WithTimeout(c.ctx, 2*time.Second)
	defer cancel()
	var topics []m.RealtimeTopic
	err := m.ErrUnavailable
	if !c.supervisor.checks.do(ctx, priority, func() { topics, err = c.supervisor.service.Authorize(ctx, c.subject, signals, resync) }) {
		return nil, m.ErrUnavailable
	}
	return topics, err
}
func (c *realtimeConnection) pings(done chan struct{}) {
	defer close(done)
	timer := time.NewTimer(20 * time.Second)
	defer timer.Stop()
	for {
		select {
		case <-c.ctx.Done():
			return
		case <-timer.C:
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			err := c.socket.Ping(ctx)
			cancel()
			if err != nil {
				c.stop(1013)
				return
			}
			timer.Reset(20 * time.Second)
		}
	}
}
func (c *realtimeConnection) send(kind string, topics []m.RealtimeTopic) error {
	converted := make([]contract.RealtimeTopic, len(topics))
	for i, topic := range topics {
		converted[i] = contract.RealtimeTopic(topic)
	}
	var value any
	switch kind {
	case "ready":
		value = contract.RealtimeReady{Type: contract.RealtimeReadyTypeReady, Version: 1, Topics: converted}
	case "resync":
		value = contract.RealtimeResync{Type: contract.Resync, Version: 1, Topics: converted}
	case "invalidate":
		value = contract.RealtimeInvalidation{Type: contract.Invalidate, Version: 1, Topics: converted}
	default:
		value = contract.RealtimeHeartbeat{Type: contract.Heartbeat, Version: 1}
	}
	body, err := json.Marshal(value)
	if err != nil || len(body) > 512 {
		return m.ErrUnavailable
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	return c.socket.Write(ctx, websocket.MessageText, body)
}
func errorCode(err error) int {
	if errors.Is(err, m.ErrUnauthorized) {
		return 4401
	}
	if errors.Is(err, m.ErrForbidden) {
		return 4403
	}
	return 1013
}
func closeReason(code int) string {
	switch code {
	case 4401:
		return "session ended"
	case 4403:
		return "permission required"
	case 1008:
		return "invalid protocol"
	case 1009:
		return "message too large"
	case 1001:
		return "connection ended"
	case 1000:
		return "closed"
	default:
		return "temporarily unavailable"
	}
}
