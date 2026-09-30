package processor

import (
	"context"
	"errors"
	"testing"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func newCapacityTestProcessor(t *testing.T, embeddingSlots int) *LocalDocumentProcessorDataSource {
	t.Helper()
	lifetime, cancel := context.WithCancel(t.Context())
	runtime, err := NewOllamaEmbeddingDataSource("http://ollama.test")
	if err != nil {
		t.Fatal(err)
	}
	cache, err := openCache(t.TempDir(), t.TempDir(), runtime)
	if err != nil {
		cancel()
		runtime.Close()
		t.Fatal(err)
	}
	local := &LocalDocumentProcessorDataSource{ctx: lifetime, cancel: cancel, runtime: runtime, cache: cache, pdfCacheDirectory: t.TempDir(), extractSlot: make(chan struct{}, models.MaxConcurrentProcessing), embedSlot: make(chan struct{}, embeddingSlots)}
	t.Cleanup(local.Close)
	return local
}

func waitForProcessorRequests(t *testing.T, local *LocalDocumentProcessorDataSource, count int) {
	t.Helper()
	deadline := time.NewTimer(time.Second)
	defer deadline.Stop()
	tick := time.NewTicker(time.Millisecond)
	defer tick.Stop()
	for {
		local.mutex.Lock()
		actual := local.requests
		local.mutex.Unlock()
		if actual == count {
			return
		}
		select {
		case <-deadline.C:
			t.Fatalf("processor has %d registered requests, want %d", actual, count)
		case <-tick.C:
		}
	}
}

func occupyProcessorSlots(slot chan struct{}) {
	for range cap(slot) {
		slot <- struct{}{}
	}
}

func TestProcessorCapacityWaitsForCPUAndResumes(t *testing.T) {
	local := newCapacityTestProcessor(t, 64)
	occupyProcessorSlots(local.extractSlot)
	finished := make(chan error, 1)
	go func() {
		_, done, err := local.begin(t.Context(), local.extractSlot)
		if err == nil {
			done()
		}
		finished <- err
	}()
	waitForProcessorRequests(t, local, 1)
	select {
	case err := <-finished:
		t.Fatalf("CPU waiter returned before capacity was available: %v", err)
	default:
	}
	if cap(local.extractSlot) != 10 || len(local.extractSlot) != 10 {
		t.Fatal("CPU concurrency exceeded ten")
	}
	<-local.extractSlot
	select {
	case err := <-finished:
		if err != nil {
			t.Fatalf("CPU waiter did not reuse released capacity: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("CPU waiter did not resume")
	}
	waitForProcessorRequests(t, local, 0)
}

func TestProcessorCapacityWaitingPreservesCallerCancellation(t *testing.T) {
	for _, deadline := range []bool{false, true} {
		t.Run(map[bool]string{false: "cancel", true: "deadline"}[deadline], func(t *testing.T) {
			local := newCapacityTestProcessor(t, 64)
			occupyProcessorSlots(local.extractSlot)
			ctx, cancel := context.WithCancel(t.Context())
			want := context.Canceled
			if deadline {
				cancel()
				ctx, cancel = context.WithTimeout(t.Context(), 50*time.Millisecond)
				want = context.DeadlineExceeded
			}
			defer cancel()
			finished := make(chan error, 1)
			go func() {
				_, done, err := local.begin(ctx, local.extractSlot)
				if err == nil {
					done()
				}
				finished <- err
			}()
			waitForProcessorRequests(t, local, 1)
			if !deadline {
				cancel()
			}
			select {
			case err := <-finished:
				if !errors.Is(err, want) {
					t.Fatalf("waiter lost caller cancellation: %v", err)
				}
			case <-time.After(time.Second):
				t.Fatal("cancelled CPU waiter did not drain")
			}
			waitForProcessorRequests(t, local, 0)
		})
	}
}

func TestProcessorCapacityRejectsExcessWaiters(t *testing.T) {
	local := newCapacityTestProcessor(t, 2)
	occupyProcessorSlots(local.extractSlot)
	finished := make(chan error, 10)
	for range 10 {
		go func() {
			_, done, err := local.begin(t.Context(), local.extractSlot)
			if err == nil {
				done()
			}
			finished <- err
		}()
	}
	waitForProcessorRequests(t, local, 10)
	_, _, err := local.begin(t.Context(), local.extractSlot)
	var failure records.DocumentProcessorError
	if !errors.As(err, &failure) || failure.Code != "overloaded" {
		t.Fatalf("excess waiter was not bounded: %v", err)
	}
	local.cancel()
	for range 10 {
		select {
		case err := <-finished:
			if !errors.As(err, &failure) || failure.Code != "inference_unavailable" {
				t.Fatalf("shutdown waiter lost retryable error: %v", err)
			}
		case <-time.After(time.Second):
			t.Fatal("shutdown did not drain waiters")
		}
	}
	waitForProcessorRequests(t, local, 0)
}

func TestProcessorCloseCancelsWaitersAndJoinsActiveRequests(t *testing.T) {
	local := newCapacityTestProcessor(t, 1)
	job, done, err := local.begin(t.Context(), local.embedSlot)
	if err != nil {
		t.Fatal(err)
	}
	activeDone := done
	defer func() {
		if activeDone != nil {
			activeDone()
		}
	}()
	waiter := make(chan error, 1)
	go func() {
		_, done, err := local.begin(t.Context(), local.embedSlot)
		if err == nil {
			done()
		}
		waiter <- err
	}()
	waitForProcessorRequests(t, local, 2)
	closed := make(chan struct{})
	go func() { local.Close(); close(closed) }()
	select {
	case <-job.Done():
	case <-time.After(time.Second):
		t.Fatal("Close did not cancel the active request")
	}
	select {
	case err := <-waiter:
		var failure records.DocumentProcessorError
		if !errors.As(err, &failure) || failure.Code != "inference_unavailable" {
			t.Fatalf("Close did not interrupt the queued request: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("Close did not cancel the queued request")
	}
	select {
	case <-closed:
		t.Fatal("Close returned before the active request drained")
	default:
	}
	activeDone()
	activeDone = nil
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("Close did not join drained requests")
	}
	if _, _, err := local.begin(t.Context(), local.embedSlot); err == nil {
		t.Fatal("closed processor admitted a new request")
	}
}
