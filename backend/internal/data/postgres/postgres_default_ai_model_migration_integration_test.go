//go:build integration

package postgres

import (
	"testing"
	"testing/fstest"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
)

func TestDefaultAIModelMigrationPreservesExistingConfiguration(t *testing.T) {
	files := fstest.MapFS{}
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.Name() >= "036" {
			continue
		}
		name := "migrations/" + entry.Name()
		contents, err := migrations.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		files[name] = &fstest.MapFile{Data: contents}
	}
	for _, scenario := range []struct {
		name, existingModel, expectedModel string
	}{
		{"fresh", "", "qwen3.5:4b"},
		{"retained default", "gemma3:4b", "gemma3:4b"},
		{"retained custom", "custom:latest", "custom:latest"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			source := migrationSource(t, testdb.New(t))
			var previousUpdated time.Time
			if scenario.existingModel != "" {
				if err := source.migrate(t.Context(), files); err != nil {
					t.Fatal(err)
				}
				migrationSQL(t, source, "UPDATE chat_configuration SET model=$1,context_length=65536 WHERE singleton", scenario.existingModel)
				if err := source.pool.QueryRow(t.Context(), "SELECT updated_at FROM chat_configuration WHERE singleton").Scan(&previousUpdated); err != nil {
					t.Fatal(err)
				}
			}
			for range 2 {
				if err := source.Migrate(t.Context()); err != nil {
					t.Fatal(err)
				}
				var model, columnDefault string
				var revision, contextLength int
				var updated time.Time
				if err := source.pool.QueryRow(t.Context(), "SELECT model,revision,context_length,updated_at FROM chat_configuration WHERE singleton").Scan(&model, &revision, &contextLength, &updated); err != nil {
					t.Fatal(err)
				}
				if model != scenario.expectedModel || revision != 1 {
					t.Fatalf("configuration changed: model=%s revision=%d", model, revision)
				}
				if scenario.existingModel != "" {
					if contextLength != 65536 || !updated.Equal(previousUpdated) {
						t.Fatal("migration changed retained context or configuration timestamp")
					}
				} else if contextLength != 32768 {
					t.Fatal("fresh context default changed")
				}
				if err := source.pool.QueryRow(t.Context(), "SELECT column_default FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='chat_configuration' AND column_name='model'").Scan(&columnDefault); err != nil || columnDefault != "'qwen3.5:4b'::text" {
					t.Fatalf("incorrect future row default: %s %v", columnDefault, err)
				}
			}
		})
	}
}
