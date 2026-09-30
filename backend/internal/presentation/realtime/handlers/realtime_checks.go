package handlers

import "context"

func newRealtimeCheckScheduler() *realtimeCheckScheduler {
	s := &realtimeCheckScheduler{requests: make(chan *realtimeCheckRequest, 128), stop: make(chan struct{}), done: make(chan struct{})}
	go s.run()
	return s
}
func (s *realtimeCheckScheduler) run() {
	defer close(s.done)
	completed := make(chan struct{}, 3)
	var high, normal []*realtimeCheckRequest
	active := 0
	for {
		for active < 3 && (len(high) > 0 || len(normal) > 0) {
			var request *realtimeCheckRequest
			if len(high) > 0 {
				request = high[0]
				high = high[1:]
			} else {
				request = normal[0]
				normal = normal[1:]
			}
			if request.ctx.Err() != nil {
				close(request.done)
				continue
			}
			active++
			go func() { defer func() { _ = recover(); close(request.done); completed <- struct{}{} }(); request.run() }()
		}
		select {
		case request := <-s.requests:
			if request.priority {
				high = append(high, request)
			} else {
				normal = append(normal, request)
			}
		case <-completed:
			active--
		case <-s.stop:
			for _, queue := range [][]*realtimeCheckRequest{high, normal} {
				for _, request := range queue {
					close(request.done)
				}
			}
			for active > 0 {
				<-completed
				active--
			}
			return
		}
	}
}
func (s *realtimeCheckScheduler) do(ctx context.Context, priority bool, run func()) bool {
	request := &realtimeCheckRequest{ctx: ctx, priority: priority, run: run, done: make(chan struct{})}
	select {
	case s.requests <- request:
	case <-ctx.Done():
		return false
	case <-s.stop:
		return false
	}
	select {
	case <-request.done:
		return ctx.Err() == nil
	case <-ctx.Done():
		// The closure owns result storage until it has returned.
		select {
		case <-request.done:
		case <-s.done:
		}
		return false
	case <-s.stop:
		select {
		case <-request.done:
		case <-s.done:
		}
		return false
	}
}
func (s *realtimeCheckScheduler) close() { close(s.stop); <-s.done }
