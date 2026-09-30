package config_test

import (
	"testing"

	"github.com/domabas/domabas/backend/internal/config"
)

func TestIngestionCapacityConfiguration(t *testing.T) {
	for _, scenario := range []struct {
		capacity, queue string
		valid           bool
	}{
		{"1", "128", true}, {"3", "6", true}, {"10", "128", true}, {"64", "128", true},
		{"auto", "128", true}, {"auto", "3", true}, {"auto", "2", true}, {"auto", "1", true},
		{"63", "127", true}, {"64", "127", false}, {"-1", "128", false}, {"9999999999999999999999999", "128", false},
		{"0", "128", false}, {"65", "128", false}, {"x", "128", false}, {"3", "3", false},
		{"2", "1", false}, {"1", "0", false}, {"1", "-1", false}, {"1", "x", false},
	} {
		t.Run(scenario.capacity+"/"+scenario.queue, func(t *testing.T) {
			t.Setenv("DOMABAS_ENV_FILE", "")
			t.Setenv("DATABASE_URL", "postgres://local/test")
			t.Setenv("DOCUMENT_INGESTION_CONCURRENCY", scenario.capacity)
			t.Setenv("DOCUMENT_AI_CONCURRENCY", "1")
			t.Setenv("OLLAMA_MAX_QUEUE", scenario.queue)
			got, err := config.Load()
			if (err == nil) != scenario.valid {
				t.Fatalf("capacity configuration: %+v %v", got, err)
			}
			if err == nil && scenario.capacity == "auto" && (got.DocumentIngestionConcurrency != max(1, got.OllamaMaxQueue/2) || got.DocumentIngestionConcurrencyMode != "ollama_half_queue") {
				t.Fatalf("automatic capacity did not reserve half the queue: %+v", got)
			}
		})
	}
}

func TestAICapacityConfiguration(t *testing.T) {
	for _, value := range []string{"auto", "1", "7", "8", "0", "", "invalid"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv("DOMABAS_ENV_FILE", "")
			t.Setenv("DATABASE_URL", "postgres://local/test")
			t.Setenv("DOCUMENT_INGESTION_CONCURRENCY", "1")
			t.Setenv("DOCUMENT_AI_CONCURRENCY", value)
			t.Setenv("OLLAMA_MAX_QUEUE", "15")
			got, err := config.Load()
			valid := value == "auto" || value == "1" || value == "7"
			if (err == nil) != valid {
				t.Fatalf("AI configuration: %+v %v", got, err)
			}
			if value == "auto" && (got.DocumentAIConcurrency != 7 || got.DocumentAIConcurrencyMode != "ollama_half_queue") {
				t.Fatalf("AI automatic capacity: %+v", got)
			}
			if value == "7" && got.DocumentAIConcurrencyMode != "fixed" {
				t.Fatalf("explicit capacity incorrectly marked automatic: %+v", got)
			}
		})
	}
}
