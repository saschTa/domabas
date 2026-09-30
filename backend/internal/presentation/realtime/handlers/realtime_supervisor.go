package handlers

import (
	"context"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
)

func NewRealtimeSupervisor(service RealtimeService, origins []string) *RealtimeSupervisor {
	ctx, cancel := context.WithCancel(context.Background())
	s := &RealtimeSupervisor{service: service, ctx: ctx, cancel: cancel, clients: map[*realtimeConnection]bool{}, users: map[string]int{}, tokens: 16, lastToken: time.Now(), initial: make(chan struct{}, 1), checks: newRealtimeCheckScheduler(), ingress: make(chan m.RealtimeSignal, 256), overflow: make(chan struct{}, 1), origins: append([]string(nil), origins...)}
	s.wg.Add(1)
	go s.fanout()
	return s
}
func (s *RealtimeSupervisor) Ping(context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.healthy || s.draining {
		return m.ErrUnavailable
	}
	return nil
}
func (s *RealtimeSupervisor) SetHealthy(healthy bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.healthy == healthy {
		return
	}
	s.healthy = healthy
	s.epoch++
	if !healthy {
		for client := range s.clients {
			client.stop(1013)
		}
	}
}
func (s *RealtimeSupervisor) Publish(signal m.RealtimeSignal) {
	select {
	case s.ingress <- signal:
	default:
		select {
		case s.overflow <- struct{}{}:
		default:
		}
	}
}
func (s *RealtimeSupervisor) fanout() {
	defer s.wg.Done()
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-s.overflow:
			s.mu.Lock()
			for client, authenticated := range s.clients {
				if authenticated {
					client.invalidate(m.RealtimeSignal{}, true)
				}
			}
			s.mu.Unlock()
		case signal := <-s.ingress:
			s.mu.Lock()
			for client, authenticated := range s.clients {
				if !authenticated {
					continue
				}
				if (signal.Kind == "email" || signal.Kind == "authority") && signal.UserID != client.subject.UserID {
					continue
				}
				client.invalidate(signal, false)
			}
			s.mu.Unlock()
		}
	}
}
func (s *RealtimeSupervisor) reserve() (*realtimeConnection, int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	s.tokens = min(16, s.tokens+now.Sub(s.lastToken).Seconds()*4)
	s.lastToken = now
	if s.tokens < 1 {
		return nil, 429
	}
	s.tokens--
	if !s.healthy || s.draining {
		return nil, 503
	}
	if len(s.clients) >= 128 || s.pending >= 16 {
		return nil, 429
	}
	ctx, cancel := context.WithTimeout(s.ctx, 30*time.Minute)
	s.phase++
	c := &realtimeConnection{supervisor: s, ctx: ctx, cancel: cancel, epoch: s.epoch, candidates: map[m.RealtimeSignal]bool{}, wake: make(chan struct{}, 1), closeCode: 1001, heartbeatOffset: time.Duration(s.phase%128) * 20 * time.Second / 128}
	s.clients[c] = false
	s.pending++
	s.wg.Add(1)
	return c, 0
}
func (s *RealtimeSupervisor) authenticate(c *realtimeConnection, subject m.RealtimeSubject) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.healthy || s.draining || c.epoch != s.epoch || c.ctx.Err() != nil {
		return false
	}
	if s.users[subject.UserID] >= 4 {
		return false
	}
	c.subject = subject
	s.clients[c] = true
	s.pending--
	s.users[subject.UserID]++
	return true
}
func (s *RealtimeSupervisor) release(c *realtimeConnection) {
	c.cancel()
	s.mu.Lock()
	defer s.mu.Unlock()
	if authenticated, ok := s.clients[c]; ok {
		if authenticated {
			s.users[c.subject.UserID]--
			if s.users[c.subject.UserID] == 0 {
				delete(s.users, c.subject.UserID)
			}
		} else {
			s.pending--
		}
		delete(s.clients, c)
		s.wg.Done()
	}
}
func (c *realtimeConnection) stop(code int)    { c.setCode(code); c.cancel() }
func (c *realtimeConnection) setCode(code int) { c.mu.Lock(); c.closeCode = code; c.mu.Unlock() }
func (c *realtimeConnection) invalidate(signal m.RealtimeSignal, resync bool) {
	c.mu.Lock()
	if resync || len(c.candidates) >= 64 {
		c.resync = true
		clear(c.candidates)
	} else if !c.resync {
		c.candidates[signal] = true
	}
	c.mu.Unlock()
	select {
	case c.wake <- struct{}{}:
	default:
	}
}
func (c *realtimeConnection) batch() ([]m.RealtimeSignal, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	signals := make([]m.RealtimeSignal, 0, len(c.candidates))
	for signal := range c.candidates {
		signals = append(signals, signal)
	}
	clear(c.candidates)
	resync := c.resync
	c.resync = false
	return signals, resync
}
func (s *RealtimeSupervisor) Close() {
	s.closeOnce.Do(func() {
		s.mu.Lock()
		s.draining = true
		s.healthy = false
		for client := range s.clients {
			client.stop(1001)
		}
		s.mu.Unlock()
		s.cancel()
		s.wg.Wait()
		s.checks.close()
	})
}
