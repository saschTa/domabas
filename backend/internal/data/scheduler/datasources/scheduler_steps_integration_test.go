//go:build integration

package datasources

import (
	"context"
	"slices"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
)

func TestExternalInferenceRunsWhileEmbeddingsAreAtCapacity(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	first, second := f.paperless(), f.paperless()
	external := "https://model.example.test"
	if !f.reserve(first, "embedding-runtime", external) || !f.reserve(second, "embedding-runtime", external) {
		t.Fatal("provider capacity blocked admission")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	entered := make(chan struct{})
	release := make(chan struct{})
	done := make(chan error, 1)
	go func() {
		done <- f.source.RunStep(ctx, first, "stage:embedding", func(ctx context.Context) error {
			close(entered)
			select {
			case <-release:
				return nil
			case <-ctx.Done():
				return ctx.Err()
			}
		})
	}()
	select {
	case <-entered:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	if err := f.source.RunStep(ctx, second, "stage:ocr", func(context.Context) error { return nil }); err != nil {
		t.Fatal(err)
	}
	if err := f.source.RunResources(ctx, second, "inference", []string{"stage:llm", f.source.ResourceID(external)}, func(context.Context) error { return nil }); err != nil {
		t.Fatalf("external inference waited for embedding capacity: %v", err)
	}
	waitctx, stop := context.WithTimeout(ctx, 120*time.Millisecond)
	defer stop()
	if err := f.source.RunStep(waitctx, second, "stage:embedding", func(context.Context) error { t.Error("provider overcommitted"); return nil }); err == nil {
		t.Fatal("waiter did not observe cancellation")
	}
	settings, err := f.service.Settings(ctx, actor)
	if err != nil {
		t.Fatal(err)
	}
	for _, resource := range settings.Resources {
		want := map[string]int{"embedding-runtime": 1, "stage:embedding": 1, "stage:llm": 0, "stage:ocr": 0, "pipeline:paperless": 2, "worker": 2, f.source.ResourceID(external): 0}
		if n, ok := want[resource.ID]; ok && n != resource.ActiveJobs {
			t.Fatalf("%s reports %d, want %d", resource.ID, resource.ActiveJobs, n)
		}
	}
	for _, pipeline := range settings.Pipelines {
		if pipeline.ID == "paperless" && (pipeline.ActiveSlots["stage:embedding"] != 1 || pipeline.ActiveSlots["embedding-runtime"] != 1 || pipeline.ActiveSlots["worker"] != 2) {
			t.Fatalf("actual pipeline reservations missing: %+v", pipeline)
		}
		if pipeline.ID == "document_ingestion" && pipeline.ActiveSlots["stage:embedding"] != 0 {
			t.Fatalf("attributed another pipeline's embedding to ingestion: %+v", pipeline)
		}
	}
	_, err = f.service.UpdateSettings(ctx, actor, m.SchedulerSettingsUpdate{ExpectedRevision: settings.Revision, Resources: []m.SchedulerResourceUpdate{{ID: "stage:paperless", Limit: 3}}})
	if err != nil {
		t.Fatal(err)
	}
	var downloads int
	if err = f.connection.QueryRow(ctx, "SELECT retrieval_concurrency FROM paperless_admission").Scan(&downloads); err != nil || downloads != 3 {
		t.Fatal("download cap", downloads, err)
	}
	close(release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if err = f.source.RunStep(ctx, second, "stage:embedding", func(context.Context) error { return nil }); err != nil {
		t.Fatal(err)
	}
}

func TestLiveFlowAttributesInferenceToTheExecutingBranch(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	id := f.paperless()
	endpoint := "https://prior-provider.example.test"
	provider := f.source.ResourceID(endpoint)
	if !f.reserve(id, endpoint) {
		t.Fatal("could not admit test job")
	}
	for _, branch := range []string{"invoice", "tags"} {
		err := f.source.RunResources(t.Context(), id, "pipeline:"+branch+"/inference", []string{"stage:llm", provider}, func(ctx context.Context) error {
			settings, err := f.service.Settings(ctx, actor)
			if err != nil {
				return err
			}
			for _, p := range settings.Pipelines {
				if p.ID == branch {
					if p.ActiveSlots["stage:llm"] != 1 || p.ActiveSlots[provider] != 1 || !slices.Contains(p.ResourceIDs, provider) {
						t.Fatalf("active retained provider missing from %s: %+v", branch, p)
					}
				} else if p.ActiveSlots[provider] != 0 || p.ActiveSlots["stage:llm"] != 0 {
					t.Fatalf("provider was also charged to %s", p.ID)
				}
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}
