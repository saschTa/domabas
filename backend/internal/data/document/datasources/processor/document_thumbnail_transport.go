package processor

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"os/exec"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func runThumbnailWorker(ctx context.Context, reader io.Reader, writer io.Writer, mediaType string) error {
	ctx, cancel := context.WithTimeout(ctx, time.Minute)
	defer cancel()
	extractor, err := NewDocumentFileExtractor(os.Getenv("DOCUMENT_PDF_CACHE_ROOT"))
	if err != nil {
		return err
	}
	defer extractor.Close()
	result, err := extractor.RenderThumbnail(ctx, reader, mediaType)
	if err != nil {
		safe := records.DocumentProcessorError{Code: "processing_failed"}
		_ = errors.As(err, &safe)
		if ctx.Err() != nil {
			safe.Code = "processing_timeout"
		}
		return json.NewEncoder(writer).Encode(safe)
	}
	_, err = writer.Write(result.Bytes)
	return err
}

func (l *LocalDocumentProcessorDataSource) RenderThumbnail(ctx context.Context, reader io.Reader, mediaType string) (records.DocumentThumbnailResult, error) {
	result := records.DocumentThumbnailResult{}
	if mediaType != "application/pdf" && mediaType != "image/png" && mediaType != "image/jpeg" {
		return result, records.DocumentProcessorError{Code: "unsupported_media"}
	}
	operation, cancel := context.WithTimeout(ctx, time.Minute)
	defer cancel()
	job, done, err := l.begin(operation, l.extractSlot)
	if err != nil {
		return result, err
	}
	defer done()
	command := exec.CommandContext(job, l.executable, "worker", "thumbnail", mediaType)
	command.Env = []string{"DOCUMENT_PDF_CACHE_ROOT=" + l.pdfCacheDirectory}
	command.Stdin = io.LimitReader(documentProcessorContextReader{job, reader}, MaxFileBytes+1)
	output := &documentProcessorBoundedBuffer{limit: models.MaxThumbnailBytes}
	command.Stdout = output
	command.Stderr = io.Discard
	configureProcess(command)
	err = command.Run()
	if ctx.Err() != nil {
		return result, ctx.Err()
	}
	if l.ctx.Err() != nil {
		return result, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	if job.Err() != nil {
		return result, records.DocumentProcessorError{Code: "processing_timeout"}
	}
	if output.exceeded {
		return result, records.DocumentProcessorError{Code: "resource_limit"}
	}
	if err != nil {
		return result, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if !bytes.HasPrefix(output.Bytes(), []byte{0xff, 0xd8}) {
		var failure records.DocumentProcessorError
		if json.Unmarshal(output.Bytes(), &failure) != nil || failure.Code == "" {
			return result, records.DocumentProcessorError{Code: "processing_failed"}
		}
		return result, failure
	}
	return validateThumbnailJPEG(output.Bytes())
}

func (remote *RemoteDocumentProcessorDataSource) RenderThumbnail(ctx context.Context, reader io.Reader, mediaType string) (records.DocumentThumbnailResult, error) {
	result := records.DocumentThumbnailResult{}
	ctx, cancel := context.WithTimeout(ctx, 75*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, remote.base+"/internal/v1/thumbnail", io.LimitReader(documentProcessorContextReader{ctx, reader}, MaxFileBytes+1))
	if err != nil {
		return result, err
	}
	request.Header.Set("Content-Type", mediaType)
	response, err := remote.client.Do(request)
	if err != nil {
		if ctx.Err() != nil {
			return result, ctx.Err()
		}
		return result, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	defer response.Body.Close()
	limit := models.MaxThumbnailBytes
	if response.StatusCode != http.StatusOK {
		limit = 4096
	}
	if response.ContentLength > int64(limit) {
		return result, records.DocumentProcessorError{Code: "processing_failed"}
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, int64(limit)+1))
	if ctx.Err() != nil {
		return result, ctx.Err()
	}
	if err != nil || len(data) > limit {
		return result, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if response.StatusCode != http.StatusOK {
		var failure records.DocumentProcessorError
		if json.Unmarshal(data, &failure) != nil {
			return result, records.DocumentProcessorError{Code: "inference_unavailable"}
		}
		switch failure.Code {
		case "invalid_file", "encrypted_pdf", "resource_limit", "processing_failed", "processing_timeout", "overloaded", "unsupported_media":
		default:
			failure.Code = "inference_unavailable"
		}
		return result, failure
	}
	if response.Header.Get("Content-Type") != "image/jpeg" {
		return result, records.DocumentProcessorError{Code: "processing_failed"}
	}
	return validateThumbnailJPEG(data)
}
