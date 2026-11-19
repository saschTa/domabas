package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/domabas/domabas/backend/internal/config"
)

func TestEnvironmentOverridesCheckedInDefaults(t *testing.T) {
	file := filepath.Join(t.TempDir(), ".env")
	if err := os.WriteFile(file, []byte("DATABASE_URL=postgres://local/db\nHTTP_ADDR=127.0.0.1:8080\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("DOMABAS_ENV_FILE", file)
	t.Setenv("DATABASE_URL", "postgres://ci/test")
	t.Setenv("HTTP_ADDR", "127.0.0.1:9090")
	loaded, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if loaded.DatabaseURL != "postgres://ci/test" || loaded.HTTPAddress != "127.0.0.1:9090" {
		t.Fatalf("overrides lost: %+v", loaded)
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
