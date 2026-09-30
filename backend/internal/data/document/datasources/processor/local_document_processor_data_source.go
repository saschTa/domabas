package processor

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type LocalDocumentProcessorDataSource struct {
	weights, executable    string
	pdfCacheDirectory      string
	cache                  *documentProcessorCache
	runtime                *OllamaEmbeddingDataSource
	extractSlot, embedSlot chan struct{}
	ctx                    context.Context
	cancel                 context.CancelFunc
	mutex                  sync.Mutex
	closed                 bool
	requests               int
	jobs                   sync.WaitGroup
}

func NewLocalDocumentProcessorDataSource(ctx context.Context, weightsRoot, ollamaRoot, ollamaURL string, ollamaMaxQueue int) (*LocalDocumentProcessorDataSource, error) {
	if ollamaMaxQueue < 1 {
		return nil, errors.New("Ollama queue capacity must be positive")
	}
	runtime, err := NewOllamaEmbeddingDataSource(ollamaURL)
	if err != nil {
		return nil, err
	}
	verified, err := openCache(weightsRoot, ollamaRoot, runtime)
	if err != nil {
		runtime.Close()
		return nil, err
	}
	fail := func(err error) (*LocalDocumentProcessorDataSource, error) {
		verified.Close()
		runtime.Close()
		return nil, err
	}
	startup, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()
	version := exec.CommandContext(startup, "tesseract", "--version")
	output := &documentProcessorBoundedBuffer{limit: 4096}
	version.Stdout = output
	version.Stderr = io.Discard
	if err = version.Run(); err != nil || !strings.HasPrefix(output.String(), "tesseract ") {
		return fail(errors.New("Tesseract unavailable"))
	}
	lines := strings.Split(output.String(), "\n")
	if len(lines) < 1 || strings.TrimSpace(lines[0]) != "tesseract "+EngineVersion {
		return fail(errors.New("unexpected Tesseract version"))
	}
	if err = runtime.wait(startup); err != nil {
		return fail(err)
	}
	if err = verified.bootstrap(startup); err != nil {
		return fail(err)
	}
	executable, err := os.Executable()
	if err != nil {
		return fail(err)
	}
	weightsRoot, err = filepath.Abs(weightsRoot)
	if err != nil {
		return fail(err)
	}
	pdfCacheDirectory, err := os.MkdirTemp("", "domabas-pdf-cache-")
	if err != nil {
		return fail(fmt.Errorf("create PDF compilation cache: %w", err))
	}
	extractor, err := NewDocumentFileExtractor(pdfCacheDirectory)
	if err == nil {
		err = errors.Join(extractor.WarmPDF(startup), extractor.Close())
	}
	if err != nil {
		return fail(errors.Join(err, os.RemoveAll(pdfCacheDirectory)))
	}
	lifetime, stop := context.WithCancel(ctx)
	return &LocalDocumentProcessorDataSource{weights: weightsRoot, executable: executable, pdfCacheDirectory: pdfCacheDirectory, cache: verified, runtime: runtime, extractSlot: make(chan struct{}, models.MaxConcurrentProcessing), embedSlot: make(chan struct{}, max(1, ollamaMaxQueue/2)), ctx: lifetime, cancel: stop}, nil
}
func (l *LocalDocumentProcessorDataSource) begin(ctx context.Context, slot chan struct{}) (context.Context, func(), error) {
	job, finish, err := l.register(ctx)
	if err != nil {
		return nil, nil, err
	}
	if err := l.acquire(ctx, job, slot); err != nil {
		finish()
		return nil, nil, err
	}
	return job, func() { <-slot; finish() }, nil
}
func (l *LocalDocumentProcessorDataSource) register(ctx context.Context) (context.Context, func(), error) {
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	l.mutex.Lock()
	if l.closed || l.ctx.Err() != nil {
		l.mutex.Unlock()
		return nil, nil, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if l.requests >= max(2*cap(l.embedSlot), models.MaxConcurrentProcessing) {
		l.mutex.Unlock()
		return nil, nil, records.DocumentProcessorError{Code: "overloaded"}
	}
	l.requests++
	l.jobs.Add(1)
	job, cancel := context.WithCancel(ctx)
	stop := context.AfterFunc(l.ctx, cancel)
	l.mutex.Unlock()
	finish := func() {
		stop()
		cancel()
		l.mutex.Lock()
		l.requests--
		l.mutex.Unlock()
		l.jobs.Done()
	}
	return job, finish, nil
}
func (l *LocalDocumentProcessorDataSource) acquire(ctx, job context.Context, slot chan struct{}) error {
	select {
	case slot <- struct{}{}:
		if job.Err() == nil {
			return nil
		}
		<-slot
	case <-job.Done():
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	return records.DocumentProcessorError{Code: "inference_unavailable"}
}
func (l *LocalDocumentProcessorDataSource) Close() {
	l.mutex.Lock()
	l.closed = true
	l.cancel()
	l.mutex.Unlock()
	l.jobs.Wait()
	_ = os.RemoveAll(l.pdfCacheDirectory)
	l.cache.Close()
	l.runtime.Close()
}
func (l *LocalDocumentProcessorDataSource) Ready(ctx context.Context) error {
	if l.ctx.Err() != nil {
		return records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	return l.runtime.Ready(ctx)
}
func (l *LocalDocumentProcessorDataSource) Embed(ctx context.Context, space records.DocumentEmbeddingSpaceRecord, purpose string, inputs []string) (records.DocumentEmbeddingResult, error) {
	if space != installedEmbeddingSpace() {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "configuration_unavailable"}
	}
	if err := validateInputs(purpose, inputs); err != nil {
		return records.DocumentEmbeddingResult{}, err
	}
	job, done, err := l.begin(ctx, l.embedSlot)
	if err != nil {
		return records.DocumentEmbeddingResult{}, err
	}
	defer done()
	result, err := l.runtime.Embed(job, space, purpose, inputs)
	if err != nil && l.ctx.Err() != nil {
		return records.DocumentEmbeddingResult{}, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	return result, err
}
func (l *LocalDocumentProcessorDataSource) Extract(ctx context.Context, reader io.Reader, mediaType string, options records.DocumentProcessorOptions) (records.DocumentExtractionResult, error) {
	if options.ExtractionRevision != "" && options.ExtractionRevision != ExtractionRevision && options.ExtractionRevision != CurrentExtractionRevision {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "configuration_unavailable"}
	}
	if !validOptions(options) || (mediaType != "application/pdf" && mediaType != "image/png" && mediaType != "image/jpeg" && !(mediaType == "message/rfc822" && options.ExtractionRevision == CurrentExtractionRevision)) {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "invalid_file"}
	}
	job, done, err := l.register(ctx)
	if err != nil {
		return records.DocumentExtractionResult{}, err
	}
	defer done()
	temp, err := os.MkdirTemp("", "domabas-extract-")
	if err != nil {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "processing_failed"}
	}
	defer os.RemoveAll(temp)
	input, err := os.OpenFile(filepath.Join(temp, "input"), os.O_CREATE|os.O_EXCL|os.O_RDWR, 0600)
	if err != nil {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "processing_failed"}
	}
	defer input.Close()
	size, err := io.Copy(input, io.LimitReader(documentProcessorContextReader{job, reader}, MaxFileBytes+1))
	if err != nil {
		if ctx.Err() != nil {
			return records.DocumentExtractionResult{}, ctx.Err()
		}
		if l.ctx.Err() != nil {
			return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "inference_unavailable"}
		}
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if size > MaxFileBytes {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "resource_limit"}
	}
	if _, err = input.Seek(0, io.SeekStart); err != nil {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if err := l.acquire(ctx, job, l.extractSlot); err != nil {
		return records.DocumentExtractionResult{}, err
	}
	defer func() { <-l.extractSlot }()
	job, cancel := context.WithTimeout(job, 480*time.Second)
	defer cancel()
	command := exec.CommandContext(job, l.executable, "worker", mediaType, options.Language, options.Segmentation, options.ExtractionRevision)
	command.Env = []string{"PATH=" + os.Getenv("PATH"), "MODEL_CACHE_ROOT=" + l.weights, "DOCUMENT_PDF_CACHE_ROOT=" + l.pdfCacheDirectory, "TMPDIR=" + temp, "HOME=" + temp, "OMP_THREAD_LIMIT=1"}
	command.Stdin = input
	output := &documentProcessorBoundedBuffer{limit: MaxRPCBytes}
	diagnostics := &documentProcessorBoundedBuffer{limit: 64 << 10}
	command.Stdout = output
	command.Stderr = diagnostics
	configureProcess(command)
	err = command.Run()
	if ctx.Err() != nil {
		return records.DocumentExtractionResult{}, ctx.Err()
	}
	if l.ctx.Err() != nil {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if job.Err() != nil {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "processing_timeout"}
	}
	if output.exceeded {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "resource_limit"}
	}
	if err != nil {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "processing_failed"}
	}
	var result documentProcessorWorkerResponse
	if json.Unmarshal(output.Bytes(), &result) != nil {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if result.Error != nil {
		return records.DocumentExtractionResult{}, *result.Error
	}
	if result.Result == nil {
		return records.DocumentExtractionResult{}, records.DocumentProcessorError{Code: "processing_failed"}
	}
	return *result.Result, nil
}
func RunWorker(ctx context.Context, args []string, reader io.Reader, writer io.Writer) error {
	if len(args) == 2 && args[0] == "thumbnail" {
		return runThumbnailWorker(ctx, reader, writer, args[1])
	}
	if len(args) == 1 && args[0] == "unlock" {
		return runUnlockWorker(ctx, reader, writer)
	}
	if len(args) != 3 && len(args) != 4 {
		return errors.New("invalid worker arguments")
	}
	ctx, cancel := context.WithTimeout(ctx, 480*time.Second)
	defer cancel()
	temp, err := os.MkdirTemp("", "domabas-page-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temp)
	revision := ""
	if len(args) == 4 {
		revision = args[3]
	}
	extractor, err := NewDocumentFileExtractor(os.Getenv("DOCUMENT_PDF_CACHE_ROOT"))
	if err != nil {
		return err
	}
	defer extractor.Close()
	result, err := extractor.ExtractFile(ctx, reader, args[0], os.Getenv("MODEL_CACHE_ROOT"), temp, records.DocumentProcessorOptions{Language: args[1], Segmentation: args[2], ExtractionRevision: revision})
	response := documentProcessorWorkerResponse{Result: &result}
	if err != nil {
		safe := records.DocumentProcessorError{Code: "processing_failed"}
		_ = errors.As(err, &safe)
		response = documentProcessorWorkerResponse{Error: &safe}
	}
	return json.NewEncoder(writer).Encode(response)
}
