package processor

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"os/exec"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	pdferrors "github.com/klippa-app/go-pdfium/errors"
	"github.com/klippa-app/go-pdfium/requests"
)

func (e *DocumentFileExtractor) UnlockPDF(ctx context.Context, reader io.Reader, password string) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(documentProcessorContextReader{ctx, reader}, MaxFileBytes+1))
	if err != nil {
		return nil, err
	}
	if len(data) == 0 || int64(len(data)) > MaxFileBytes {
		return nil, records.DocumentProcessorError{Code: "resource_limit"}
	}
	pool, err := e.newPDFPool(ctx)
	if err != nil {
		return nil, pdfError(err)
	}
	defer pool.Close()
	instance, err := pool.GetInstanceWithContext(ctx)
	if err != nil {
		return nil, pdfError(err)
	}
	defer instance.Close()
	document, err := instance.OpenDocument(&requests.OpenDocument{File: &data, Password: &password})
	if errors.Is(err, pdferrors.ErrPassword) {
		return nil, records.DocumentProcessorError{Code: "invalid_pdf_password"}
	}
	if err != nil {
		return nil, pdfError(err)
	}
	output := &documentProcessorBoundedBuffer{limit: int(MaxFileBytes)}
	_, err = instance.FPDF_SaveAsCopy(&requests.FPDF_SaveAsCopy{Document: document.Document, Flags: requests.SaveFlagRemoveSecurity, FileWriter: output})
	if output.exceeded {
		return nil, records.DocumentProcessorError{Code: "resource_limit"}
	}
	if err != nil {
		return nil, pdfError(err)
	}
	unlocked := output.Bytes()
	if _, err = instance.OpenDocument(&requests.OpenDocument{File: &unlocked}); err != nil {
		return nil, pdfError(err)
	}
	return unlocked, nil
}

func unlockInput(reader io.Reader, password string) io.Reader {
	prefix := make([]byte, 4+len(password))
	binary.BigEndian.PutUint32(prefix, uint32(len(password)))
	copy(prefix[4:], password)
	return io.MultiReader(bytes.NewReader(prefix), reader)
}

func runUnlockWorker(ctx context.Context, reader io.Reader, writer io.Writer) error {
	ctx, cancel := context.WithTimeout(ctx, 110*time.Second)
	defer cancel()
	var prefix [4]byte
	if _, err := io.ReadFull(reader, prefix[:]); err != nil {
		return err
	}
	length := binary.BigEndian.Uint32(prefix[:])
	if length < 1 || length > 1024 {
		return errors.New("invalid password length")
	}
	password := make([]byte, length)
	if _, err := io.ReadFull(reader, password); err != nil {
		return err
	}
	extractor, err := NewDocumentFileExtractor(os.Getenv("DOCUMENT_PDF_CACHE_ROOT"))
	if err != nil {
		return err
	}
	defer extractor.Close()
	result, err := extractor.UnlockPDF(ctx, reader, string(password))
	clear(password)
	if err != nil {
		safe := records.DocumentProcessorError{Code: "processing_failed"}
		_ = errors.As(err, &safe)
		return json.NewEncoder(writer).Encode(safe)
	}
	_, err = writer.Write(result)
	return err
}

func (l *LocalDocumentProcessorDataSource) UnlockPDF(ctx context.Context, reader io.Reader, password string) ([]byte, error) {
	job, done, err := l.begin(ctx, l.extractSlot)
	if err != nil {
		return nil, err
	}
	defer done()
	job, cancel := context.WithTimeout(job, 110*time.Second)
	defer cancel()
	command := exec.CommandContext(job, l.executable, "worker", "unlock")
	command.Env = []string{"PATH=" + os.Getenv("PATH"), "DOCUMENT_PDF_CACHE_ROOT=" + l.pdfCacheDirectory}
	command.Stdin = unlockInput(io.LimitReader(reader, MaxFileBytes+1), password)
	output := &documentProcessorBoundedBuffer{limit: int(MaxFileBytes)}
	command.Stdout = output
	command.Stderr = io.Discard
	configureProcess(command)
	err = command.Run()
	if job.Err() != nil {
		return nil, records.DocumentProcessorError{Code: "processing_timeout"}
	}
	if output.exceeded {
		return nil, records.DocumentProcessorError{Code: "resource_limit"}
	}
	if err != nil {
		return nil, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if !bytes.HasPrefix(output.Bytes(), []byte("%PDF-")) {
		var failure records.DocumentProcessorError
		if json.Unmarshal(output.Bytes(), &failure) != nil {
			return nil, records.DocumentProcessorError{Code: "processing_failed"}
		}
		return nil, failure
	}
	return output.Bytes(), nil
}

func (remote *RemoteDocumentProcessorDataSource) UnlockPDF(ctx context.Context, reader io.Reader, password string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 115*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, remote.base+"/internal/v1/unlock", unlockInput(reader, password))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/octet-stream")
	response, err := remote.client.Do(request)
	if err != nil {
		return nil, records.DocumentProcessorError{Code: "inference_unavailable"}
	}
	defer response.Body.Close()
	limit := int64(MaxFileBytes)
	if response.StatusCode != http.StatusOK {
		limit = 4096
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
	if err != nil || int64(len(data)) > limit {
		return nil, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if response.StatusCode != http.StatusOK {
		var failure records.DocumentProcessorError
		if json.Unmarshal(data, &failure) != nil {
			return nil, records.DocumentProcessorError{Code: "processing_failed"}
		}
		return nil, failure
	}
	if !bytes.HasPrefix(data, []byte("%PDF-")) {
		return nil, records.DocumentProcessorError{Code: "processing_failed"}
	}
	return data, nil
}
