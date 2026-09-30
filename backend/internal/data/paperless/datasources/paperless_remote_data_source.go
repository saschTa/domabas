package datasources

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"
	"unicode/utf8"

	r "github.com/domabas/domabas/backend/internal/data/paperless/models"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type PaperlessRemoteDataSource struct {
	mu          sync.Mutex
	nextRequest time.Time
	client      *http.Client
}

func NewPaperlessRemoteDataSource() *PaperlessRemoteDataSource {
	dialer := &paperlessGuardedDialer{resolver: net.DefaultResolver, dial: (&net.Dialer{Timeout: 5 * time.Second}).DialContext}
	transport := &http.Transport{Proxy: nil, DialContext: dialer.DialContext, TLSHandshakeTimeout: 5 * time.Second, ResponseHeaderTimeout: 10 * time.Second, MaxResponseHeaderBytes: 32768, DisableKeepAlives: true, DisableCompression: true, MaxConnsPerHost: m.MaxRetrievalConcurrency}
	return &PaperlessRemoteDataSource{client: &http.Client{Transport: transport, Timeout: 45 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
}
func (s *PaperlessRemoteDataSource) get(ctx context.Context, c m.PaperlessConnection, path string) (*http.Response, error) {
	server, err := normalizeServerURL(c.ServerURL)
	if err != nil {
		return nil, err
	}
	if len(c.Token) < 1 || len(c.Token) > 256 {
		return nil, m.PaperlessFailure{Code: "invalid_request"}
	}
	for _, ch := range c.Token {
		if ch < 33 || ch > 126 {
			return nil, m.PaperlessFailure{Code: "invalid_request"}
		}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, server+"/api/"+path, nil)
	if err != nil {
		return nil, m.PaperlessFailure{Code: "invalid_request"}
	}
	req.Header.Set("Authorization", "Token "+c.Token)
	req.Header.Set("Accept", "application/json; version=9")
	s.mu.Lock()
	wait := time.Until(s.nextRequest)
	if wait > 0 {
		timer := time.NewTimer(wait)
		select {
		case <-ctx.Done():
			timer.Stop()
			s.mu.Unlock()
			return nil, m.PaperlessFailure{Code: "source_unavailable"}
		case <-timer.C:
		}
	}
	s.nextRequest = time.Now().Add(100 * time.Millisecond)
	s.mu.Unlock()
	response, err := s.client.Do(req)
	if err != nil {
		var failure m.PaperlessFailure
		if errors.As(err, &failure) {
			return nil, failure
		}
		return nil, m.PaperlessFailure{Code: "source_unavailable"}
	}
	if response.StatusCode != http.StatusOK {
		response.Body.Close()
		code := "source_unavailable"
		switch response.StatusCode {
		case 401, 403:
			code = "source_unauthorized"
		case 404:
			code = "source_not_found"
		case 406:
			code = "source_incompatible"
		case 429:
			code = "source_busy"
		}
		return nil, m.PaperlessFailure{Code: code}
	}
	return response, nil
}
func (s *PaperlessRemoteDataSource) json(ctx context.Context, c m.PaperlessConnection, path string, result any) error {
	response, err := s.get(ctx, c, path)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, (1<<20)+1))
	if err != nil {
		return m.PaperlessFailure{Code: "source_unavailable"}
	}
	if len(body) > 1<<20 || !utf8.Valid(body) || json.Unmarshal(body, result) != nil {
		return m.PaperlessFailure{Code: "source_incompatible"}
	}
	return nil
}
func (s *PaperlessRemoteDataSource) Page(ctx context.Context, c m.PaperlessConnection, page int) (r.PaperlessPageRecord, error) {
	var result r.PaperlessPageRecord
	err := s.json(ctx, c, "documents/?page_size=100&ordering=id&fields=id,title&page="+strconv.Itoa(page), &result)
	return result, err
}
func (s *PaperlessRemoteDataSource) Document(ctx context.Context, c m.PaperlessConnection, id int64) (r.PaperlessDocumentRecord, error) {
	var result r.PaperlessDocumentRecord
	err := s.json(ctx, c, "documents/"+strconv.FormatInt(id, 10)+"/?fields=id,title,created,original_file_name,tags,correspondent,document_type,archive_serial_number", &result)
	return result, err
}
func (s *PaperlessRemoteDataSource) Name(ctx context.Context, c m.PaperlessConnection, collection string, id int64) (string, error) {
	if (collection != "tags" && collection != "correspondents" && collection != "document_types") || id < 1 || id > 2147483647 {
		return "", m.PaperlessFailure{Code: "source_incompatible"}
	}
	var result r.PaperlessNamedRecord
	if err := s.json(ctx, c, collection+"/"+strconv.FormatInt(id, 10)+"/", &result); err != nil {
		return "", err
	}
	if result.ID != id {
		return "", m.PaperlessFailure{Code: "source_incompatible"}
	}
	return result.Name, nil
}
func (s *PaperlessRemoteDataSource) Download(ctx context.Context, c m.PaperlessConnection, id int64) (io.ReadCloser, error) {
	response, err := s.get(ctx, c, "documents/"+strconv.FormatInt(id, 10)+"/download/?original=true")
	if err != nil {
		return nil, err
	}
	if response.ContentLength > d.MaxFileBytes {
		response.Body.Close()
		return nil, d.ErrTooLarge
	}
	return response.Body, nil
}
