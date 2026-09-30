package processor

import (
	"context"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
)

type documentProcessorReadFunc func([]byte) (int, error)

func (read documentProcessorReadFunc) Read(buffer []byte) (int, error) { return read(buffer) }

func TestRemoteExtractionPreservesCallerDeadlineAndCancellation(t *testing.T) {
	for _, bounded := range []bool{false, true} {
		t.Run(map[bool]string{false: "without_deadline", true: "with_deadline"}[bounded], func(t *testing.T) {
			ctx, cancel := context.WithCancel(t.Context())
			if bounded {
				cancel()
				ctx, cancel = context.WithTimeout(t.Context(), time.Hour)
			}
			defer cancel()
			deadline, hasDeadline := ctx.Deadline()
			remote, err := NewRemoteDocumentProcessorDataSource("http://processor.test")
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			entered := make(chan struct{})
			remote.client.Transport = documentEmbeddingTransport(func(request *http.Request) (*http.Response, error) {
				got, present := request.Context().Deadline()
				if present != hasDeadline || !got.Equal(deadline) {
					t.Errorf("extraction changed the caller deadline: %v, want %v", got, deadline)
				}
				close(entered)
				<-request.Context().Done()
				return nil, request.Context().Err()
			})
			finished := make(chan error, 1)
			go func() {
				_, err := remote.Extract(ctx, strings.NewReader("%PDF"), "application/pdf", records.DocumentProcessorOptions{Language: "eng", Segmentation: "auto"})
				finished <- err
			}()
			select {
			case <-entered:
			case <-time.After(time.Second):
				t.Fatal("extraction did not reach the private processor")
			}
			cancel()
			select {
			case err := <-finished:
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("extraction cancellation category lost: %v", err)
				}
			case <-time.After(time.Second):
				t.Fatal("extraction did not drain")
			}
		})
	}
}

func TestExtractionSpoolsAcceptedBodyBeforeWaitingForCPU(t *testing.T) {
	for _, shutdown := range []bool{false, true} {
		t.Run(map[bool]string{false: "caller_cancels", true: "processor_closes"}[shutdown], func(t *testing.T) {
			local := newCapacityTestProcessor(t, 64)
			occupyProcessorSlots(local.extractSlot)
			temporary := t.TempDir()
			t.Setenv("TMPDIR", temporary)
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			body := strings.NewReader("%PDF-test-body")
			consumed := make(chan struct{})
			reader := documentProcessorReadFunc(func(buffer []byte) (int, error) {
				local.mutex.Lock()
				registered := local.requests
				local.mutex.Unlock()
				if registered != 1 {
					t.Errorf("body was read outside bounded request registration: %d", registered)
				}
				n, err := body.Read(buffer)
				if err == io.EOF {
					close(consumed)
				}
				return n, err
			})
			finished := make(chan error, 1)
			go func() {
				_, err := local.Extract(ctx, reader, "application/pdf", records.DocumentProcessorOptions{Language: "eng", Segmentation: "auto"})
				finished <- err
			}()
			select {
			case <-consumed:
			case <-time.After(time.Second):
				t.Fatal("queued extraction left the request body unread")
			}
			files, err := filepath.Glob(filepath.Join(temporary, "domabas-extract-*", "input"))
			if err != nil || len(files) != 1 {
				t.Fatalf("queued extraction did not retain one private input file: %v, %v", files, err)
			}
			data, err := os.ReadFile(files[0])
			if err != nil || string(data) != "%PDF-test-body" {
				t.Fatalf("queued extraction lost spooled content: %q, %v", data, err)
			}
			select {
			case err := <-finished:
				t.Fatalf("extraction did not wait for the occupied CPU slots: %v", err)
			default:
			}
			closed := make(chan struct{})
			if shutdown {
				go func() { local.Close(); close(closed) }()
			} else {
				cancel()
			}
			select {
			case err := <-finished:
				var failure records.DocumentProcessorError
				if shutdown && (!errors.As(err, &failure) || failure.Code != "inference_unavailable") {
					t.Fatalf("processor shutdown was not retryable: %v", err)
				}
				if !shutdown && !errors.Is(err, context.Canceled) {
					t.Fatalf("caller cancellation was lost: %v", err)
				}
			case <-time.After(time.Second):
				t.Fatal("queued extraction did not drain")
			}
			if shutdown {
				select {
				case <-closed:
				case <-time.After(time.Second):
					t.Fatal("processor close did not join queued extraction")
				}
			}
			waitForProcessorRequests(t, local, 0)
			if _, err := os.Stat(filepath.Dir(files[0])); !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("drained extraction left private input behind: %v", err)
			}
		})
	}
}

func TestExtractionRejectsBodyBeforeReadingWhenRequestCapacityIsFull(t *testing.T) {
	local := newCapacityTestProcessor(t, 1)
	for range 10 {
		_, finish, err := local.register(t.Context())
		if err != nil {
			t.Fatal(err)
		}
		defer finish()
	}
	reader := documentProcessorReadFunc(func([]byte) (int, error) {
		t.Error("overloaded extraction started reading its body")
		return 0, io.EOF
	})
	_, err := local.Extract(t.Context(), reader, "application/pdf", records.DocumentProcessorOptions{Language: "eng", Segmentation: "auto"})
	var failure records.DocumentProcessorError
	if !errors.As(err, &failure) || failure.Code != "overloaded" {
		t.Fatalf("unbounded extraction request was accepted: %v", err)
	}
}

func TestExtractionBodyFailureReleasesAdmissionAndTemporaryFiles(t *testing.T) {
	for _, scenario := range []string{"read_failure", "caller_cancels", "processor_stops"} {
		t.Run(scenario, func(t *testing.T) {
			local := newCapacityTestProcessor(t, 64)
			occupyProcessorSlots(local.extractSlot)
			temporary := t.TempDir()
			t.Setenv("TMPDIR", temporary)
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			reader := documentProcessorReadFunc(func([]byte) (int, error) {
				if scenario == "caller_cancels" {
					cancel()
				}
				if scenario == "processor_stops" {
					local.cancel()
				}
				return 0, io.ErrUnexpectedEOF
			})
			_, err := local.Extract(ctx, reader, "application/pdf", records.DocumentProcessorOptions{Language: "eng", Segmentation: "auto"})
			var failure records.DocumentProcessorError
			if scenario == "caller_cancels" {
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("body read lost caller cancellation: %v", err)
				}
			} else {
				code := "processing_failed"
				if scenario == "processor_stops" {
					code = "inference_unavailable"
				}
				if !errors.As(err, &failure) || failure.Code != code {
					t.Fatalf("body read returned the wrong failure: %v", err)
				}
			}
			waitForProcessorRequests(t, local, 0)
			files, err := os.ReadDir(temporary)
			if err != nil || len(files) != 0 {
				t.Fatalf("failed body left private temporary files: %v, %v", files, err)
			}
		})
	}
}
