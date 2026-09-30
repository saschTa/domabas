package bootstrap

import (
	"errors"
	"sync"
	"sync/atomic"
)

type managedTemporalWorker interface {
	Start() error
	Stop()
}

type temporalWorkerLifecycle struct {
	worker   managedTemporalWorker
	drain    func()
	started  chan struct{}
	stopOnce sync.Once
	ready    atomic.Bool
	failed   atomic.Bool
	fatal    chan error
}

func newTemporalWorkerLifecycle(drain func()) *temporalWorkerLifecycle {
	return &temporalWorkerLifecycle{drain: drain, started: make(chan struct{}), fatal: make(chan error, 1)}
}

func (owner *temporalWorkerLifecycle) Start(worker managedTemporalWorker) error {
	owner.worker = worker
	err := worker.Start()
	owner.ready.Store(err == nil && !owner.failed.Load())
	close(owner.started)
	if err != nil {
		owner.Close()
	}
	return err
}

func (owner *temporalWorkerLifecycle) Close() {
	owner.ready.Store(false)
	<-owner.started
	owner.stopOnce.Do(func() {
		owner.ready.Store(false)
		owner.worker.Stop()
		owner.drain()
	})
}

func (owner *temporalWorkerLifecycle) onFatalError(err error) {
	if !owner.failed.CompareAndSwap(false, true) {
		return
	}
	owner.ready.Store(false)
	// The SDK can also stop after this callback; finish the shared drain first.
	owner.Close()
	owner.fatal <- err
}

func (owner *temporalWorkerLifecycle) Ping() error {
	if !owner.ready.Load() || owner.failed.Load() {
		return errors.New("Temporal worker is not running")
	}
	return nil
}
