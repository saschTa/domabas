package llm

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"
)

type documentInferenceTransport func(*http.Request) (*http.Response, error)

func (transport documentInferenceTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	return transport(request)
}

func TestInferenceUsesCallerDeadlineAndCancellation(t *testing.T) {
	const provider = "openai"
	t.Run(provider, func(t *testing.T) {
		remote := NewDocumentPropertyRemoteDataSource()
		defer remote.Close()
		ctx, cancel := context.WithTimeout(t.Context(), time.Hour)
		defer cancel()
		deadline, _ := ctx.Deadline()
		entered := make(chan struct{})
		remote.client.Transport = documentInferenceTransport(func(request *http.Request) (*http.Response, error) {
			got, ok := request.Context().Deadline()
			if !ok || !got.Equal(deadline) {
				t.Errorf("model request shortened caller deadline: %v, want %v", got, deadline)
			}
			close(entered)
			<-request.Context().Done()
			return nil, request.Context().Err()
		})
		finished := make(chan error, 1)
		go func() {
			_, err := remote.Extract(ctx, provider, "model", "http://model.test", "", "Synthetic document", true, false)
			finished <- err
		}()
		select {
		case <-entered:
		case <-time.After(time.Second):
			t.Fatal("request did not reach the model")
		}
		cancel()
		select {
		case err := <-finished:
			if !errors.Is(err, context.Canceled) {
				t.Fatalf("request cancellation category lost: %v", err)
			}
		case <-time.After(time.Second):
			t.Fatal("model request did not drain on cancellation")
		}
	})
}
