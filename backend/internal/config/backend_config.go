package config

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

type BackendConfig struct {
	DocumentIngestionConcurrency     int
	DocumentAIConcurrency            int
	DocumentIngestionConcurrencyMode string
	DocumentAIConcurrencyMode        string
	OllamaMaxQueue                   int
	LLMOllamaURL                     string
	LLMCredentialKey                 string
	LLMCredentialKeyFile             string
	PaperlessCredentialKey           string
	PaperlessCredentialKeyFile       string
	DatabaseURL                      string
	HTTPAddress                      string
	CORSOrigins                      []string
	TemporalUIURL                    string
	TemporalAddress                  string
	TemporalNamespace                string
	TemporalTaskQueue                string
	DocumentProcessorURL             string
	DocumentIngestionRoot            string
	DocumentStorageRoot              string
	EmailCredentialKeys              string
	EmailCredentialKeyFile           string
	EmailActiveKeyID                 string
	EmailIMAPCAFile                  string
	EmailIMAPAllowedHosts            []string
}

func Load() (BackendConfig, error) {
	path, explicitPath := os.LookupEnv("DOMABAS_ENV_FILE")
	if !explicitPath {
		path = ".env"
	}
	values := map[string]string{}
	if path != "" {
		var err error
		values, err = godotenv.Read(path)
		if err != nil && (explicitPath || !errors.Is(err, os.ErrNotExist)) {
			return BackendConfig{}, fmt.Errorf("read environment file: %w", err)
		}
	}
	value := func(key, fallback string) string {
		if result, ok := os.LookupEnv(key); ok {
			return result
		}
		if result, ok := values[key]; ok {
			return result
		}
		return fallback
	}
	config := BackendConfig{DatabaseURL: value("DATABASE_URL", ""), HTTPAddress: value("HTTP_ADDR", "127.0.0.1:8080")}
	var capacityErr error
	config.OllamaMaxQueue, capacityErr = strconv.Atoi(value("OLLAMA_MAX_QUEUE", "128"))
	if capacityErr != nil || config.OllamaMaxQueue < 1 {
		return BackendConfig{}, errors.New("OLLAMA_MAX_QUEUE must be a positive integer")
	}
	config.DocumentIngestionConcurrency, config.DocumentIngestionConcurrencyMode, capacityErr = documentConcurrency("DOCUMENT_INGESTION_CONCURRENCY", value("DOCUMENT_INGESTION_CONCURRENCY", "1"), config.OllamaMaxQueue)
	if capacityErr != nil {
		return BackendConfig{}, capacityErr
	}
	config.DocumentAIConcurrency, config.DocumentAIConcurrencyMode, capacityErr = documentConcurrency("DOCUMENT_AI_CONCURRENCY", value("DOCUMENT_AI_CONCURRENCY", "1"), config.OllamaMaxQueue)
	if capacityErr != nil {
		return BackendConfig{}, capacityErr
	}
	config.TemporalUIURL = value("TEMPORAL_UI_URL", "")
	if config.TemporalUIURL == "" {
		port := value("TEMPORAL_UI_PORT", "8233")
		if port == "" {
			port = "8233"
		}
		if number, err := strconv.Atoi(port); err != nil || number < 1 || number > 65535 {
			return BackendConfig{}, errors.New("TEMPORAL_UI_PORT must be between 1 and 65535")
		}
		config.TemporalUIURL = "http://localhost:" + port
	}
	if config.TemporalUIURL != "" {
		u, e := url.Parse(config.TemporalUIURL)
		if e != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.ForceQuery || strings.Contains(config.TemporalUIURL, "#") {
			return BackendConfig{}, errors.New("TEMPORAL_UI_URL must be an absolute HTTP(S) URL without credentials, query or fragment")
		}
		if port := u.Port(); port != "" {
			n, e := strconv.Atoi(port)
			if e != nil || n < 1 || n > 65535 {
				return BackendConfig{}, errors.New("TEMPORAL_UI_URL has an invalid port")
			}
		}
		if strings.HasSuffix(u.Host, ":") {
			return BackendConfig{}, errors.New("TEMPORAL_UI_URL has an invalid port")
		}
	}
	config.TemporalAddress = value("TEMPORAL_ADDRESS", "127.0.0.1:7233")
	config.TemporalNamespace = value("TEMPORAL_NAMESPACE", "domabas")
	config.TemporalTaskQueue = value("TEMPORAL_TASK_QUEUE", "domabas-documents")
	config.EmailCredentialKeys = value("EMAIL_CREDENTIAL_KEYS", "")
	config.LLMOllamaURL = value("LLM_OLLAMA_URL", "http://127.0.0.1:11435")
	config.LLMCredentialKey = value("LLM_CREDENTIAL_KEY", "")
	config.PaperlessCredentialKey = value("PAPERLESS_CREDENTIAL_KEY", "")
	config.EmailActiveKeyID = value("EMAIL_CREDENTIAL_ACTIVE_KEY_ID", "")
	config.EmailIMAPCAFile = value("EMAIL_IMAP_CA_FILE", "")
	for _, host := range strings.Split(value("EMAIL_IMAP_ALLOWED_HOSTS", ""), ",") {
		if host = strings.TrimSpace(host); host != "" {
			config.EmailIMAPAllowedHosts = append(config.EmailIMAPAllowedHosts, host)
		}
	}
	config.DocumentProcessorURL = value("DOCUMENT_PROCESSOR_URL", "http://127.0.0.1:8091")
	processor, err := url.Parse(config.DocumentProcessorURL)
	if err != nil || (processor.Scheme != "http" && processor.Scheme != "https") || processor.Host == "" || processor.User != nil || processor.RawQuery != "" || processor.Fragment != "" || (processor.Path != "" && processor.Path != "/") {
		return BackendConfig{}, errors.New("DOCUMENT_PROCESSOR_URL must be an HTTP(S) origin")
	}
	config.DocumentIngestionRoot = value("DOCUMENT_INGESTION_ROOT", "../.cache/ingestion")
	config.DocumentStorageRoot = value("DOCUMENT_STORAGE_ROOT", "../.cache/documents")
	if strings.TrimSpace(config.DocumentIngestionRoot) == "" || strings.TrimSpace(config.DocumentStorageRoot) == "" {
		return BackendConfig{}, errors.New("DOCUMENT_INGESTION_ROOT and DOCUMENT_STORAGE_ROOT must not be empty")
	}
	config.DocumentIngestionRoot, err = filepath.Abs(config.DocumentIngestionRoot)
	if err != nil {
		return BackendConfig{}, fmt.Errorf("resolve ingestion directory: %w", err)
	}
	config.DocumentStorageRoot, err = filepath.Abs(config.DocumentStorageRoot)
	if err != nil {
		return BackendConfig{}, fmt.Errorf("resolve document directory: %w", err)
	}
	config.PaperlessCredentialKeyFile = value("PAPERLESS_CREDENTIAL_KEY_FILE", filepath.Join(config.DocumentStorageRoot, ".secrets", "paperless.key"))
	config.LLMCredentialKeyFile = value("LLM_CREDENTIAL_KEY_FILE", filepath.Join(config.DocumentStorageRoot, ".secrets", "llm.key"))
	config.EmailCredentialKeyFile = value("EMAIL_CREDENTIAL_KEY_FILE", filepath.Join(config.DocumentStorageRoot, ".secrets", "email.key"))
	if strings.TrimSpace(config.EmailCredentialKeyFile) == "" {
		return BackendConfig{}, errors.New("EMAIL_CREDENTIAL_KEY_FILE must not be empty")
	}
	config.EmailCredentialKeyFile, err = filepath.Abs(config.EmailCredentialKeyFile)
	if err != nil {
		return BackendConfig{}, fmt.Errorf("resolve email credential key file: %w", err)
	}
	if strings.TrimSpace(config.PaperlessCredentialKeyFile) == "" {
		return BackendConfig{}, errors.New("PAPERLESS_CREDENTIAL_KEY_FILE must not be empty")
	}
	config.PaperlessCredentialKeyFile, err = filepath.Abs(config.PaperlessCredentialKeyFile)
	if err != nil {
		return BackendConfig{}, fmt.Errorf("resolve Paperless credential key file: %w", err)
	}
	if config.DatabaseURL == "" {
		return BackendConfig{}, errors.New("DATABASE_URL is required")
	}
	if _, _, err := net.SplitHostPort(config.HTTPAddress); err != nil {
		return BackendConfig{}, fmt.Errorf("HTTP_ADDR must be host:port: %w", err)
	}
	if host, port, err := net.SplitHostPort(config.TemporalAddress); err != nil || host == "" || port == "" {
		return BackendConfig{}, errors.New("TEMPORAL_ADDRESS must be host:port")
	}
	if strings.TrimSpace(config.TemporalNamespace) == "" || strings.TrimSpace(config.TemporalTaskQueue) == "" {
		return BackendConfig{}, errors.New("TEMPORAL_NAMESPACE and TEMPORAL_TASK_QUEUE must not be empty")
	}
	for _, origin := range strings.Split(value("CORS_ORIGINS", "http://localhost:7357,http://127.0.0.1:7357"), ",") {
		origin = strings.TrimSpace(origin)
		if origin == "" {
			continue
		}
		parsed, err := url.Parse(origin)
		if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" || parsed.Path != "" || parsed.RawQuery != "" || parsed.Fragment != "" || parsed.User != nil {
			return BackendConfig{}, errors.New("CORS_ORIGINS must contain comma-separated HTTP(S) origins without paths")
		}
		config.CORSOrigins = append(config.CORSOrigins, origin)
	}
	return config, nil
}

func documentConcurrency(name, value string, queue int) (int, string, error) {
	limit := max(1, queue/2)
	if value == "auto" {
		return limit, "ollama_half_queue", nil
	}
	capacity, err := strconv.Atoi(value)
	if err != nil || capacity < 1 || capacity > limit {
		return 0, "", fmt.Errorf("%s must be auto or an integer between 1 and %d (half OLLAMA_MAX_QUEUE, minimum 1)", name, limit)
	}
	return capacity, "fixed", nil
}
