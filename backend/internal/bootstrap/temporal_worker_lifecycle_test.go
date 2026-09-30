package bootstrap

import (
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type lifecycleWorker struct {
	startError  error
	stops       atomic.Int32
	stopEntered chan struct{}
	stopRelease chan struct{}
}

func (worker *lifecycleWorker) Start() error { return worker.startError }
func (worker *lifecycleWorker) Stop() {
	if worker.stops.Add(1) != 1 {
		panic("overlapping SDK Stop")
	}
	if worker.stopEntered != nil {
		close(worker.stopEntered)
	}
	if worker.stopRelease != nil {
		<-worker.stopRelease
	}
}

func TestFatalErrorAndNormalCloseShareDrainBarrier(t *testing.T) {
	worker := &lifecycleWorker{stopEntered: make(chan struct{}), stopRelease: make(chan struct{})}
	drainEntered, drainRelease := make(chan struct{}), make(chan struct{})
	owner := newTemporalWorkerLifecycle(func() { close(drainEntered); <-drainRelease })
	if err := owner.Start(worker); err != nil {
		t.Fatal(err)
	}
	if err := owner.Ping(); err != nil {
		t.Fatal(err)
	}
	fatal := errors.New("namespace removed")
	go owner.onFatalError(fatal)
	<-worker.stopEntered
	if err := owner.Ping(); err == nil {
		t.Fatal("fatal worker remained ready")
	}
	var closeWait sync.WaitGroup
	for range 8 {
		closeWait.Go(owner.Close)
	}
	select {
	case <-owner.fatal:
		t.Fatal("fatal completion published before SDK stop finished")
	default:
	}
	close(worker.stopRelease)
	<-drainEntered
	select {
	case <-owner.fatal:
		t.Fatal("fatal completion published before I/O drained")
	default:
	}
	close(drainRelease)
	select {
	case got := <-owner.fatal:
		if !errors.Is(got, fatal) {
			t.Fatalf("wrong fatal error: %v", got)
		}
	case <-time.After(time.Second):
		t.Fatal("fatal shutdown deadlocked")
	}
	closeWait.Wait()
	owner.Close()
	owner.onFatalError(errors.New("duplicate callback"))
	if worker.stops.Load() != 1 {
		t.Fatal("worker stopped more than once")
	}
}

func TestStartupFailureRollsBackAndRepeatedCloseIsSafe(t *testing.T) {
	failure := errors.New("start failed")
	worker := &lifecycleWorker{startError: failure}
	var drained atomic.Int32
	owner := newTemporalWorkerLifecycle(func() { drained.Add(1) })
	if err := owner.Start(worker); !errors.Is(err, failure) {
		t.Fatalf("lost startup error: %v", err)
	}
	owner.Close()
	owner.Close()
	if owner.Ping() == nil || worker.stops.Load() != 1 || drained.Load() != 1 {
		t.Fatal("startup failure did not close resources exactly once")
	}
}

func TestNormalCloseRacingFatalErrorKeepsResourcesUntilDrain(t *testing.T) {
	worker := &lifecycleWorker{stopEntered: make(chan struct{}), stopRelease: make(chan struct{})}
	var drained atomic.Bool
	owner := newTemporalWorkerLifecycle(func() { drained.Store(true) })
	if err := owner.Start(worker); err != nil {
		t.Fatal(err)
	}
	closed := make(chan struct{})
	go func() { owner.Close(); close(closed) }()
	<-worker.stopEntered
	go owner.onFatalError(errors.New("concurrent poll failure"))
	close(worker.stopRelease)
	<-closed
	select {
	case <-owner.fatal:
		if !drained.Load() {
			t.Fatal("fatal completion preceded drain")
		}
	case <-time.After(time.Second):
		t.Fatal("normal/fatal shutdown deadlocked")
	}
	if owner.Ping() == nil || worker.stops.Load() != 1 {
		t.Fatal("invalid final worker state")
	}
}
