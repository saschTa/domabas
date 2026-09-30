package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/domabas/domabas/backend/internal/config"
)

func TestEnvironmentOverridesCheckedInDefaults(t *testing.T) {
	file := filepath.Join(t.TempDir(), ".env")
	if err := os.WriteFile(file, []byte("DATABASE_URL=postgres://local/db\nHTTP_ADDR=127.0.0.1:8080\nTEMPORAL_ADDRESS=localhost:7233\nTEMPORAL_NAMESPACE=default\nTEMPORAL_TASK_QUEUE=default\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("DOMABAS_ENV_FILE", file)
	t.Setenv("DATABASE_URL", "postgres://ci/test")
	t.Setenv("HTTP_ADDR", "127.0.0.1:9090")
	t.Setenv("TEMPORAL_ADDRESS", "temporal:7233")
	t.Setenv("TEMPORAL_NAMESPACE", "test-namespace")
	t.Setenv("TEMPORAL_TASK_QUEUE", "test-queue")
	loaded, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if loaded.DatabaseURL != "postgres://ci/test" || loaded.HTTPAddress != "127.0.0.1:9090" {
		t.Fatalf("overrides lost: %+v", loaded)
	}
	if loaded.TemporalAddress != "temporal:7233" || loaded.TemporalNamespace != "test-namespace" || loaded.TemporalTaskQueue != "test-queue" {
		t.Fatalf("Temporal overrides lost: %+v", loaded)
	}
}

func TestInvalidTemporalConfigurationFails(t *testing.T) {
	for _, scenario := range []struct{ key, value string }{
		{"TEMPORAL_ADDRESS", "missing-port"}, {"TEMPORAL_ADDRESS", ":7233"},
		{"TEMPORAL_NAMESPACE", ""}, {"TEMPORAL_TASK_QUEUE", " "},
	} {
		t.Run(scenario.key+scenario.value, func(t *testing.T) {
			t.Setenv("DOMABAS_ENV_FILE", "")
			t.Setenv("DATABASE_URL", "postgres://ci/test")
			t.Setenv(scenario.key, scenario.value)
			if _, err := config.Load(); err == nil {
				t.Fatal("invalid Temporal configuration accepted")
			}
		})
	}
}

func TestInvalidOriginsFailConfiguration(t *testing.T) {
	t.Setenv("DOMABAS_ENV_FILE", "")
	t.Setenv("DATABASE_URL", "postgres://ci/test")
	t.Setenv("CORS_ORIGINS", "*")
	if _, err := config.Load(); err == nil {
		t.Fatal("wildcard origin accepted")
	}
}

func TestDocumentConfigurationRejectsInvalidOriginsAndEmptyPaths(t *testing.T) {
	for _, scenario := range []struct{ key, value string }{
		{"DOCUMENT_PROCESSOR_URL", "file:///tmp/model"}, {"DOCUMENT_PROCESSOR_URL", "http://user:secret@localhost:8091"},
		{"DOCUMENT_PROCESSOR_URL", "http://localhost:8091/private"}, {"DOCUMENT_PROCESSOR_URL", "http://localhost:8091?token=secret"},
		{"DOCUMENT_INGESTION_ROOT", ""}, {"DOCUMENT_STORAGE_ROOT", " "},
	} {
		t.Run(scenario.key+scenario.value, func(t *testing.T) {
			t.Setenv("DOMABAS_ENV_FILE", "")
			t.Setenv("DATABASE_URL", "postgres://ci/test")
			t.Setenv(scenario.key, scenario.value)
			if _, err := config.Load(); err == nil {
				t.Fatal("invalid document configuration accepted")
			}
		})
	}
}

func TestDocumentConfigurationLoadsWithoutCreatingStorageOrConnecting(t *testing.T) {
	t.Setenv("DOMABAS_ENV_FILE", "")
	t.Setenv("DATABASE_URL", "postgres://ci/test")
	t.Setenv("DOCUMENT_PROCESSOR_URL", "http://127.0.0.1:1")
	ingestion, documents := filepath.Join(t.TempDir(), "ingestion"), filepath.Join(t.TempDir(), "documents")
	t.Setenv("DOCUMENT_INGESTION_ROOT", ingestion)
	t.Setenv("DOCUMENT_STORAGE_ROOT", documents)
	loaded, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if loaded.DocumentIngestionRoot != ingestion || loaded.DocumentStorageRoot != documents || loaded.DocumentProcessorURL != "http://127.0.0.1:1" {
		t.Fatalf("document overrides lost: %+v", loaded)
	}
	for _, path := range []string{ingestion, documents} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("configuration touched storage: %v", err)
		}
	}
}

func TestTemporalDashboardURLDefaultsToPublishedPort(t *testing.T) {
	for _, scenario := range []struct {
		name, file, want string
		env              map[string]string
	}{
		{name: "unset", want: "http://localhost:8233"},
		{name: "empty", env: map[string]string{"TEMPORAL_UI_URL": "", "TEMPORAL_UI_PORT": ""}, want: "http://localhost:8233"},
		{name: "local port", file: "TEMPORAL_UI_URL=\nTEMPORAL_UI_PORT=9233\n", want: "http://localhost:9233"},
		{name: "exported port", file: "TEMPORAL_UI_PORT=9233\n", env: map[string]string{"TEMPORAL_UI_PORT": "10233"}, want: "http://localhost:10233"},
		{name: "local URL", file: "TEMPORAL_UI_URL=https://temporal.example/ui\n", want: "https://temporal.example/ui"},
		{name: "exported URL", file: "TEMPORAL_UI_URL=https://temporal.example/ui\n", env: map[string]string{"TEMPORAL_UI_URL": "https://other.example/workflows"}, want: "https://other.example/workflows"},
		{name: "empty override", file: "TEMPORAL_UI_URL=https://temporal.example/ui\n", env: map[string]string{"TEMPORAL_UI_URL": ""}, want: "http://localhost:8233"},
		{name: "invalid port", env: map[string]string{"TEMPORAL_UI_PORT": "invalid"}},
		{name: "port with path", env: map[string]string{"TEMPORAL_UI_PORT": "8233/path"}},
		{name: "zero port", env: map[string]string{"TEMPORAL_UI_PORT": "0"}},
		{name: "out of range port", env: map[string]string{"TEMPORAL_UI_PORT": "65536"}},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			for _, key := range []string{"TEMPORAL_UI_URL", "TEMPORAL_UI_PORT"} {
				t.Setenv(key, "")
				if err := os.Unsetenv(key); err != nil {
					t.Fatal(err)
				}
			}
			file := filepath.Join(t.TempDir(), ".env")
			if err := os.WriteFile(file, []byte(scenario.file), 0600); err != nil {
				t.Fatal(err)
			}
			t.Setenv("DOMABAS_ENV_FILE", file)
			t.Setenv("DATABASE_URL", "postgres://local/test")
			for key, value := range scenario.env {
				t.Setenv(key, value)
			}
			cfg, err := config.Load()
			if scenario.want == "" {
				if err == nil {
					t.Fatal("invalid dashboard port accepted")
				}
				return
			}
			if err != nil || cfg.TemporalUIURL != scenario.want {
				t.Fatalf("dashboard URL: got %q, want %q: %v", cfg.TemporalUIURL, scenario.want, err)
			}
		})
	}
}

func TestTemporalDashboardURLIsStrict(t *testing.T) {
	for _, value := range []string{"http://127.0.0.1:8233", "https://temporal.internal/base/path"} {
		t.Run("valid="+value, func(t *testing.T) {
			t.Setenv("DOMABAS_ENV_FILE", "")
			t.Setenv("DATABASE_URL", "postgres://local/test")
			t.Setenv("TEMPORAL_UI_URL", value)
			cfg, err := config.Load()
			if err != nil || cfg.TemporalUIURL != value {
				t.Fatalf("dashboard URL: %q %v", cfg.TemporalUIURL, err)
			}
		})
	}
	for _, value := range []string{"javascript:alert(1)", "/relative", "https://user:password@internal", "http://internal?", "http://internal#", "http://internal?q=a", "http://internal#anchor", "http://internal:0", "http://internal:65536", "http://internal:"} {
		t.Run("invalid="+value, func(t *testing.T) {
			t.Setenv("DOMABAS_ENV_FILE", "")
			t.Setenv("DATABASE_URL", "postgres://local/test")
			t.Setenv("TEMPORAL_UI_URL", value)
			if _, err := config.Load(); err == nil {
				t.Fatal("unsafe dashboard URL accepted")
			}
		})
	}
}

func TestEmailKeyDefaultsToIsolatedStorageAndAllowsExplicitOverride(t *testing.T) {
	t.Setenv("DOMABAS_ENV_FILE", "")
	t.Setenv("DATABASE_URL", "postgres://local/test")
	storage := filepath.Join(t.TempDir(), "documents")
	t.Setenv("DOCUMENT_STORAGE_ROOT", storage)
	loaded, err := config.Load()
	if err != nil || loaded.EmailCredentialKeyFile != filepath.Join(storage, ".secrets", "email.key") {
		t.Fatal("default email key location is not owned by storage", err)
	}
	if _, err := os.Stat(storage); !os.IsNotExist(err) {
		t.Fatal("configuration created secrets before startup", err)
	}
	path := filepath.Join(t.TempDir(), "private.key")
	t.Setenv("EMAIL_CREDENTIAL_KEY_FILE", path)
	t.Setenv("EMAIL_CREDENTIAL_KEYS", "explicit-keyring")
	t.Setenv("EMAIL_CREDENTIAL_ACTIVE_KEY_ID", "primary")
	loaded, err = config.Load()
	if err != nil || loaded.EmailCredentialKeyFile != path || loaded.EmailCredentialKeys != "explicit-keyring" || loaded.EmailActiveKeyID != "primary" {
		t.Fatal("operator email key overrides lost", err)
	}
	t.Setenv("EMAIL_CREDENTIAL_KEY_FILE", " ")
	if _, err := config.Load(); err == nil {
		t.Fatal("empty explicit email key location accepted")
	}
}

func TestPaperlessKeyDefaultsToIsolatedStorageAndAllowsExplicitOverride(t *testing.T) {
	t.Setenv("DOMABAS_ENV_FILE", "")
	t.Setenv("DATABASE_URL", "postgres://local/test")
	storage := filepath.Join(t.TempDir(), "documents")
	t.Setenv("DOCUMENT_STORAGE_ROOT", storage)
	t.Setenv("PAPERLESS_CREDENTIAL_KEY", "")
	loaded, err := config.Load()
	if err != nil || loaded.PaperlessCredentialKeyFile != filepath.Join(storage, ".secrets", "paperless.key") {
		t.Fatal("default key location is not owned by storage", loaded.PaperlessCredentialKeyFile, err)
	}
	if _, err := os.Stat(storage); !os.IsNotExist(err) {
		t.Fatal("configuration created secrets before startup", err)
	}
	path := filepath.Join(t.TempDir(), "private.key")
	t.Setenv("PAPERLESS_CREDENTIAL_KEY_FILE", path)
	t.Setenv("PAPERLESS_CREDENTIAL_KEY", "legacy-value")
	loaded, err = config.Load()
	if err != nil || loaded.PaperlessCredentialKeyFile != path || loaded.PaperlessCredentialKey != "legacy-value" {
		t.Fatal("operator key overrides lost", err)
	}
	t.Setenv("PAPERLESS_CREDENTIAL_KEY_FILE", " ")
	if _, err := config.Load(); err == nil {
		t.Fatal("empty explicit key location accepted")
	}
}
