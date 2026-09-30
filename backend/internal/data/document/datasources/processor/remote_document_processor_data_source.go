package processor

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
)

type RemoteDocumentProcessorDataSource struct {
	base   string
	client *http.Client
}

func privateClient() *http.Client {
	return &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }, Transport: &http.Transport{Proxy: nil, DialContext: (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext, MaxIdleConns: 4, MaxIdleConnsPerHost: 2, IdleConnTimeout: 30 * time.Second, TLSHandshakeTimeout: 5 * time.Second}}
}
func validURL(base string) (string, error) {
	u, err := url.Parse(base)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return "", errors.New("processor URL must be an HTTP service origin")
	}
	return strings.TrimRight(base, "/"), nil
}
func NewRemoteDocumentProcessorDataSource(base string) (*RemoteDocumentProcessorDataSource, error) {
	base, err := validURL(base)
	if err != nil {
		return nil, err
	}
	return &RemoteDocumentProcessorDataSource{base: base, client: privateClient()}, nil
}
func (remote *RemoteDocumentProcessorDataSource) Close() { remote.client.CloseIdleConnections() }
func (remote *RemoteDocumentProcessorDataSource) request(ctx context.Context, method, path string, body io.Reader, headers map[string]string, result any) error {
	request, err := http.NewRequestWithContext(ctx, method, remote.base+path, body)
	if err != nil {
		return records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	for name, value := range headers {
		request.Header.Set(name, value)
	}
	response, err := remote.client.Do(request)
	if err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	defer response.Body.Close()
	payload, err := io.ReadAll(io.LimitReader(response.Body, MaxRPCBytes+1))
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err != nil || len(payload) > MaxRPCBytes {
		return records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if response.StatusCode != http.StatusOK {
		var failure records.DocumentProcessorError
		if json.Unmarshal(payload, &failure) != nil {
			failure.Code = "inference_unavailable"
		}
		switch failure.Code {
		case "invalid_invoice", "configuration_unavailable", "invalid_file", "encrypted_pdf", "no_text", "resource_limit", "processing_failed", "processing_timeout", "context_length", "overloaded", "too_large", "unsupported_media":
		default:
			failure.Code = "inference_unavailable"
		}
		return failure
	}
	if result == nil {
		return nil
	}
	if err = json.Unmarshal(payload, result); err != nil {
		return records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	return nil
}
func (remote *RemoteDocumentProcessorDataSource) Extract(ctx context.Context, reader io.Reader, mediaType string, options records.DocumentProcessorOptions) (records.DocumentExtractionResult, error) {
	var result records.DocumentExtractionResult
	err := remote.request(ctx, http.MethodPost, "/internal/v1/extract", reader, map[string]string{"Content-Type": mediaType, "X-Domabas-Extraction-Revision": options.ExtractionRevision, "X-Domabas-OCR-Language": options.Language, "X-Domabas-OCR-Segmentation": options.Segmentation}, &result)
	return result, err
}
func (remote *RemoteDocumentProcessorDataSource) Embed(ctx context.Context, space records.DocumentEmbeddingSpaceRecord, purpose string, inputs []string) (records.DocumentEmbeddingResult, error) {
	var result records.DocumentEmbeddingResult
	body, err := json.Marshal(documentProcessorEmbedRequest{Space: space, Purpose: purpose, Inputs: inputs})
	if err != nil {
		return result, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	err = remote.request(ctx, http.MethodPost, "/internal/v1/embed", bytes.NewReader(body), map[string]string{"Content-Type": "application/json"}, &result)
	return result, err
}
func (remote *RemoteDocumentProcessorDataSource) Ready(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	return remote.request(ctx, http.MethodGet, "/readyz", nil, nil, nil)
}
