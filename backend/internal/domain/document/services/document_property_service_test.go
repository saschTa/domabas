package services

import (
	"context"
	"errors"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type propertyRepository struct {
	work           m.DocumentPropertyWork
	saved          bool
	credential     bool
	credentialRead func(context.Context) (string, error)
}

func (r *propertyRepository) Work(context.Context, m.DocumentJob) (m.DocumentPropertyWork, error) {
	return r.work, nil
}
func (r *propertyRepository) Credential(ctx context.Context, _ string) (string, error) {
	r.credential = true
	if r.credentialRead != nil {
		return r.credentialRead(ctx)
	}
	return "key", nil
}

func TestPropertiesPreserveCancellationDuringCredentialRead(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	r := &propertyRepository{
		work: m.DocumentPropertyWork{Eligible: true, Stage: "enriching", Text: "source", Configuration: m.DocumentLLMConfiguration{Enabled: true}},
		credentialRead: func(context.Context) (string, error) {
			cancel()
			return "", errors.New("credential storage unavailable")
		},
	}
	e := &propertyExtractor{}
	if err := NewDocumentPropertyService(r, e).Enrich(ctx, m.DocumentJob{AIAttempt: 1}); !errors.Is(err, context.Canceled) || e.called || r.saved {
		t.Fatalf("credential cancellation became an AI failure: %v", err)
	}
}
func (r *propertyRepository) Save(_ context.Context, _ m.DocumentPropertyWork, v m.DocumentMetadata) error {
	r.saved = true
	return nil
}

type propertyExtractor struct {
	called bool
	values m.DocumentMetadata
	err    error
}

func (e *propertyExtractor) ExtractProperties(context.Context, m.DocumentLLMConfiguration, string, string) (m.DocumentMetadata, error) {
	e.called = true
	return e.values, e.err
}

func TestPropertiesSkipDisabledAndCompletedStages(t *testing.T) {
	for _, stage := range []string{"embedding", "finalizing", "complete"} {
		r := &propertyRepository{work: m.DocumentPropertyWork{Eligible: true, Stage: stage}}
		e := &propertyExtractor{}
		if err := NewDocumentPropertyService(r, e).Enrich(t.Context(), m.DocumentJob{}); err != nil || r.credential || e.called || r.saved {
			t.Fatalf("skipped stage %s performed work: %v", stage, err)
		}
	}
}
func TestPropertiesValidateBeforePublication(t *testing.T) {
	for _, tc := range []struct {
		name   string
		values m.DocumentMetadata
		err    error
		want   bool
	}{
		{"valid", m.DocumentMetadata{Sender: "Example", Tags: []string{"invoice"}}, nil, true},
		{"bad date", m.DocumentMetadata{DocumentDate: "2026-99-99"}, nil, false},
		{"duplicates", m.DocumentMetadata{Tags: []string{"invoice", "invoice"}}, nil, false},
		{"provider failure", m.DocumentMetadata{}, m.DocumentProcessingError{Code: "inference_unavailable", Retryable: true}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := &propertyRepository{work: m.DocumentPropertyWork{Eligible: true, Stage: "enriching", Configuration: m.DocumentLLMConfiguration{Enabled: true}}}
			e := &propertyExtractor{values: tc.values, err: tc.err}
			err := NewDocumentPropertyService(r, e).Enrich(t.Context(), m.DocumentJob{})
			if (err == nil) != tc.want || r.saved != tc.want {
				t.Fatalf("publication=%v error=%v", r.saved, err)
			}
		})
	}
}
