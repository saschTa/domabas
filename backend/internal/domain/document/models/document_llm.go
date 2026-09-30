package models

import (
	"net/url"
	"strconv"
	"strings"
)

const DefaultDocumentContextLength = 32768

func (c DocumentLLMConfiguration) RequestedContextLength() int {
	if c.ContextLength == 0 {
		return 16384
	}
	return c.ContextLength
}

func (c DocumentLLMConfiguration) Defaults() DocumentLLMConfiguration {
	if c.Provider == "" {
		c.Provider = "ollama"
	}
	if c.Model == "" {
		c.Model = "gemma3:4b"
	}
	return c
}

func (c DocumentLLMConfiguration) InvoiceExtractionEnabled() bool {
	if c.InvoiceEnabled == nil {
		return c.Enabled
	}
	return *c.InvoiceEnabled
}

func (c DocumentLLMConfiguration) Equal(other DocumentLLMConfiguration) bool {
	invoiceEnabled := c.InvoiceExtractionEnabled() == other.InvoiceExtractionEnabled()
	c.InvoiceEnabled, other.InvoiceEnabled = nil, nil
	return invoiceEnabled && c.Defaults() == other.Defaults()
}

func (c DocumentLLMConfiguration) Validate() error {
	c = c.Defaults()
	if c.ContextLength != 0 && (c.ContextLength < 1024 || c.ContextLength > 1048576) {
		return DocumentValidationError{"context length must be between 1024 and 1048576 tokens"}
	}
	if c.Provider != "ollama" && c.Provider != "openai" {
		return DocumentValidationError{"invalid property extraction provider"}
	}
	if !validText(c.Model, 128, 128, false) || strings.TrimSpace(c.Model) == "" || strings.ContainsAny(c.Model, " \t\r\n") {
		return DocumentValidationError{"invalid property extraction model"}
	}
	if c.Provider == "ollama" {
		if c.BaseURL != "" || c.CredentialID != "" {
			return DocumentValidationError{"internal Ollama does not use an external URL or credential"}
		}
		return nil
	}
	u, err := url.Parse(c.BaseURL)
	if err != nil || !validText(c.BaseURL, 2048, 2048, false) || u.Hostname() == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" || strings.ContainsAny(c.BaseURL, "\\\r\n") {
		return DocumentValidationError{"external base URL must be an absolute HTTP(S) URL without credentials, query or fragment"}
	}
	if u.Port() != "" {
		p, err := strconv.Atoi(u.Port())
		if err != nil || p < 1 || p > 65535 {
			return DocumentValidationError{"invalid external service port"}
		}
	}
	return nil
}

func (u DocumentLLMConfigurationUpdate) Normalize() (DocumentLLMConfigurationUpdate, error) {
	if u.ContextLength != nil && (*u.ContextLength < 1024 || *u.ContextLength > 1048576) {
		return u, DocumentValidationError{"context length must be between 1024 and 1048576 tokens"}
	}
	u.Model, u.BaseURL = strings.TrimSpace(u.Model), strings.TrimRight(strings.TrimSpace(u.BaseURL), "/")
	if u.Model == "" || u.Provider == "" {
		return u, DocumentValidationError{"property extraction provider and model are required"}
	}
	if err := (DocumentLLMConfiguration{Enabled: u.Enabled, Provider: u.Provider, Model: u.Model, BaseURL: u.BaseURL}).Validate(); err != nil {
		return u, err
	}
	if u.APIKey != nil && (u.ClearAPIKey || *u.APIKey == "" || !validText(*u.APIKey, 4096, 4096, false) || strings.TrimSpace(*u.APIKey) != *u.APIKey || u.Provider != "openai") {
		return u, DocumentValidationError{"invalid property extraction credential"}
	}
	return u, nil
}
