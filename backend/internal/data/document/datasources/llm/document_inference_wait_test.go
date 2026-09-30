package llm

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

type documentInferenceTransport func(*http.Request) (*http.Response, error)

func (transport documentInferenceTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	return transport(request)
}

func TestInferenceUsesCallerDeadlineAndCancellation(t *testing.T) {
	for _, provider := range []string{"ollama", "openai"} {
		t.Run(provider, func(t *testing.T) {
			remote, err := NewDocumentPropertyRemoteDataSource("http://model.test")
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			ctx, cancel := context.WithTimeout(t.Context(), time.Hour)
			defer cancel()
			deadline, _ := ctx.Deadline()
			entered := make(chan struct{})
			remote.client.Transport = documentInferenceTransport(func(request *http.Request) (*http.Response, error) {
				if request.URL.Path == "/api/show" {
					return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":131072}}`)), Header: http.Header{}}, nil
				}
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
}
