package processor

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
)

type documentProcessorCache struct {
	weights   *os.Root
	modelPath string
	client    *http.Client
	runtime   *LlamaEmbeddingDataSource
}

func openCache(weightsPath, modelPath string, runtime *LlamaEmbeddingDataSource) (*documentProcessorCache, error) {
	if err := os.MkdirAll(weightsPath, 0700); err != nil {
		return nil, err
	}
	weights, err := os.OpenRoot(weightsPath)
	if err != nil {
		return nil, err
	}
	return &documentProcessorCache{weights: weights, modelPath: modelPath, client: &http.Client{Timeout: 90 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}, runtime: runtime}, nil
}
func (c *documentProcessorCache) Close() {
	c.weights.Close()
	c.client.CloseIdleConnections()
}
func verifyArtifact(ctx context.Context, root *os.Root, expected documentProcessorArtifact) error {
	file, err := root.Open(expected.Name)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Size() != expected.Size {
		return fmt.Errorf("artifact size mismatch: %s", expected.Name)
	}
	digest := sha256.New()
	if _, err = io.Copy(digest, documentProcessorContextReader{ctx: ctx, reader: file}); err != nil {
		return err
	}
	if hex.EncodeToString(digest.Sum(nil)) != expected.SHA256 {
		return fmt.Errorf("artifact digest mismatch: %s", expected.Name)
	}
	return nil
}
func syncCacheDirectory(root *os.Root) error {
	dir, err := root.Open(".")
	if err != nil {
		return err
	}
	return errors.Join(dir.Sync(), dir.Close())
}
func (c *documentProcessorCache) downloadWeight(ctx context.Context, expected documentProcessorArtifact) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, weightBase+expected.Name, nil)
	if err != nil {
		return err
	}
	response, err := c.client.Do(request)
	if err != nil {
		return errors.New("weight download unavailable")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return errors.New("weight download refused")
	}
	temporary := ".download-" + uuid.NewString()
	file, err := c.weights.OpenFile(temporary, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	defer func() { _ = file.Close(); _ = c.weights.Remove(temporary) }()
	digest := sha256.New()
	size, err := io.Copy(io.MultiWriter(file, digest), io.LimitReader(response.Body, expected.Size+1))
	if err != nil || size != expected.Size || hex.EncodeToString(digest.Sum(nil)) != expected.SHA256 {
		return fmt.Errorf("downloaded weight verification failed: %s", expected.Name)
	}
	if err = file.Sync(); err != nil {
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	if err = c.weights.Rename(temporary, expected.Name); err != nil {
		return err
	}
	return syncCacheDirectory(c.weights)
}
func (c *documentProcessorCache) removeInterruptedDownloads(ctx context.Context) error {
	directory, err := c.weights.Open(".")
	if err != nil {
		return err
	}
	defer directory.Close()
	for {
		entries, readErr := directory.ReadDir(100)
		for _, entry := range entries {
			if err := ctx.Err(); err != nil {
				return err
			}
			if !strings.HasPrefix(entry.Name(), ".download-") {
				continue
			}
			id, parseErr := uuid.Parse(strings.TrimPrefix(entry.Name(), ".download-"))
			if parseErr == nil && entry.Name() == ".download-"+id.String() {
				if err := c.weights.Remove(entry.Name()); err != nil && !errors.Is(err, fs.ErrNotExist) {
					return err
				}
			}
		}
		if errors.Is(readErr, io.EOF) {
			return directory.Sync()
		}
		if readErr != nil {
			return readErr
		}
	}
}
func (c *documentProcessorCache) bootstrap(ctx context.Context) error {
	lock, err := c.weights.OpenFile(".bootstrap.lock", os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err = lockCache(ctx, lock); err != nil {
		return err
	}
	defer unlockCache(lock)
	if err = c.removeInterruptedDownloads(ctx); err != nil {
		return err
	}
	for _, artifact := range weightArtifacts() {
		err = verifyArtifact(ctx, c.weights, artifact)
		if errors.Is(err, fs.ErrNotExist) {
			err = c.downloadWeight(ctx, artifact)
		}
		if err != nil {
			return err
		}
	}
	modelDirectory, err := os.OpenRoot(filepath.Dir(c.modelPath))
	if err != nil {
		return fmt.Errorf("open embedding model directory: %w", err)
	}
	defer modelDirectory.Close()
	if err := verifyArtifact(ctx, modelDirectory, documentProcessorArtifact{filepath.Base(c.modelPath), modelSize, ModelDigest}); err != nil {
		return fmt.Errorf("verify embedding GGUF: %w", err)
	}
	_, err = c.runtime.Embed(ctx, installedEmbeddingSpace(), "query", []string{"document processor readiness"})
	return err
}

type documentProcessorContextReader struct {
	ctx    context.Context
	reader io.Reader
}

func (r documentProcessorContextReader) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.reader.Read(p)
}

func requestJSON(ctx context.Context, client *http.Client, method, url string, value any, limit int64) ([]byte, int, error) {
	var body io.Reader
	if value != nil {
		data, err := json.Marshal(value)
		if err != nil {
			return nil, 0, err
		}
		body = bytes.NewReader(data)
	}
	request, err := http.NewRequestWithContext(ctx, method, url, body)
	if err != nil {
		return nil, 0, err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := client.Do(request)
	if err != nil {
		return nil, 0, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
	if err != nil {
		return nil, response.StatusCode, err
	}
	if int64(len(data)) > limit {
		return nil, response.StatusCode, errors.New("bounded response exceeded")
	}
	return data, response.StatusCode, nil
}
