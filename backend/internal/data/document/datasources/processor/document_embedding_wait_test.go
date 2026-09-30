package processor

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
)

type documentEmbeddingTransport func(*http.Request) (*http.Response, error)

func (transport documentEmbeddingTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	return transport(request)
}

func TestEmbeddingPreservesCallerDeadlineAndCancellationAcrossBothHops(t *testing.T) {
	for _, direct := range []bool{false, true} {
		ctx, cancel := context.WithTimeout(t.Context(), time.Hour)
		deadline, _ := ctx.Deadline()
		entered := make(chan struct{})
		transport := documentEmbeddingTransport(func(request *http.Request) (*http.Response, error) {
			if request.URL.Path == "/api/tags" {
				data, _ := json.Marshal(map[string]any{"models": []map[string]string{{"name": ModelName, "digest": ModelDigest}}})
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(string(data)))}, nil
			}
			got, ok := request.Context().Deadline()
			if !ok || !got.Equal(deadline) {
				t.Errorf("embedding request shortened caller deadline: %v, want %v", got, deadline)
			}
			close(entered)
			<-request.Context().Done()
			return nil, request.Context().Err()
		})
		var embed func(context.Context, records.DocumentEmbeddingSpaceRecord, string, []string) (records.DocumentEmbeddingResult, error)
		if direct {
			remote, err := NewOllamaEmbeddingDataSource("http://ollama.test")
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			remote.client.Transport = transport
			embed = remote.Embed
		} else {
			remote, err := NewRemoteDocumentProcessorDataSource("http://processor.test")
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			remote.client.Transport = transport
			embed = remote.Embed
		}
		finished := make(chan error, 1)
		go func() {
			_, err := embed(ctx, installedEmbeddingSpace(), "document", []string{"Synthetic text"})
			finished <- err
		}()
		select {
		case <-entered:
		case <-time.After(time.Second):
			cancel()
			t.Fatal("embedding did not reach the model")
		}
		cancel()
		select {
		case err := <-finished:
			if !errors.Is(err, context.Canceled) {
				t.Fatalf("embedding cancellation category lost: %v", err)
			}
		case <-time.After(time.Second):
			t.Fatal("embedding did not drain")
		}
	}
}

func TestProcessorShutdownKeepsInterruptedEmbeddingRetryable(t *testing.T) {
	lifetime, stop := context.WithCancel(t.Context())
	defer stop()
	remote, err := NewOllamaEmbeddingDataSource("http://ollama.test")
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	remote.client.Transport = documentEmbeddingTransport(func(request *http.Request) (*http.Response, error) {
		if request.URL.Path == "/api/tags" {
			data, _ := json.Marshal(map[string]any{"models": []map[string]string{{"name": ModelName, "digest": ModelDigest}}})
			return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(string(data)))}, nil
		}
		stop()
		<-request.Context().Done()
		return nil, request.Context().Err()
	})
	local := &LocalDocumentProcessorDataSource{ctx: lifetime, cancel: stop, embedSlot: make(chan struct{}, 1), runtime: remote}
	_, err = local.Embed(t.Context(), installedEmbeddingSpace(), "document", []string{"Synthetic text"})
	var failure records.DocumentProcessorError
	if !errors.As(err, &failure) || failure.Code != "inference_unavailable" || t.Context().Err() != nil {
		t.Fatalf("processor restart became a terminal document timeout: %v", err)
	}
}

func TestProcessorSupportsMoreThanTenConcurrentEmbeddingRequests(t *testing.T) {
	local := newCapacityTestProcessor(t, 64)
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	entered := make(chan struct{}, 65)
	local.runtime.client.Transport = documentEmbeddingTransport(func(request *http.Request) (*http.Response, error) {
		if request.URL.Path == "/api/tags" {
			data, _ := json.Marshal(map[string]any{"models": []map[string]string{{"name": ModelName, "digest": ModelDigest}}})
			return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(string(data)))}, nil
		}
		entered <- struct{}{}
		<-request.Context().Done()
		return nil, request.Context().Err()
	})
	finished := make(chan error, 65)
	embed := func() {
		_, err := local.Embed(ctx, installedEmbeddingSpace(), "document", []string{"Synthetic text"})
		finished <- err
	}
	for range 64 {
		go embed()
	}
	for range 64 {
		select {
		case <-entered:
		case err := <-finished:
			t.Fatalf("embedding failed before all 64 requests reached the model: %v", err)
		case <-time.After(time.Second):
			t.Fatal("configured embedding concurrency was not available")
		}
	}
	go embed()
	waitForProcessorRequests(t, local, 65)
	select {
	case <-entered:
		t.Fatal("embedding exceeded configured capacity")
	case err := <-finished:
		t.Fatalf("embedding queue returned instead of waiting: %v", err)
	default:
	}
	cancel()
	for range 65 {
		select {
		case err := <-finished:
			if !errors.Is(err, context.Canceled) {
				t.Fatalf("embedding cancellation was not preserved: %v", err)
			}
		case <-time.After(time.Second):
			t.Fatal("embedding request failed to drain")
		}
	}
	waitForProcessorRequests(t, local, 0)
}
