package filesystem

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/domabas/domabas/backend/internal/data/document/datasources/mimecontent"
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

const maxFileBytes = models.MaxFileBytes

type DocumentFileSystemDataSource struct{ ingestion, final *os.Root }

func NewDocumentFileSystemDataSource(ingestionPath, finalPath string) (*DocumentFileSystemDataSource, error) {
	ingestionPath, err := prepareRoot(ingestionPath)
	if err != nil {
		return nil, fmt.Errorf("prepare ingestion directory: %w", err)
	}
	finalPath, err = prepareRoot(finalPath)
	if err != nil {
		return nil, fmt.Errorf("prepare document directory: %w", err)
	}
	if overlaps(ingestionPath, finalPath) {
		return nil, errors.New("ingestion and final directories must not overlap")
	}
	ingestion, err := os.OpenRoot(ingestionPath)
	if err != nil {
		return nil, err
	}
	final, err := os.OpenRoot(finalPath)
	if err != nil {
		ingestion.Close()
		return nil, err
	}
	return &DocumentFileSystemDataSource{ingestion: ingestion, final: final}, nil
}

func prepareRoot(name string) (string, error) {
	if strings.TrimSpace(name) == "" {
		return "", errors.New("storage directory is required")
	}
	absolute, err := filepath.Abs(name)
	if err != nil {
		return "", err
	}
	if err = os.MkdirAll(absolute, 0700); err != nil {
		return "", err
	}
	info, err := os.Lstat(absolute)
	if err != nil {
		return "", err
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm()&0077 != 0 || !owned(info) {
		return "", errors.New("storage root must be an owned private directory")
	}
	return filepath.EvalSymlinks(absolute)
}
func overlaps(left, right string) bool {
	rel, err := filepath.Rel(left, right)
	if err == nil && (rel == "." || rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))) {
		return true
	}
	rel, err = filepath.Rel(right, left)
	return err == nil && (rel == "." || rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)))
}
func (source *DocumentFileSystemDataSource) Close() error {
	return errors.Join(source.ingestion.Close(), source.final.Close())
}
func storageError(err error) error {
	if err == nil {
		return nil
	}
	return records.DocumentProcessorError{Code: "storage_unavailable"}
}
func relative(ref records.DocumentContentReference) (string, error) {
	ids := []string{ref.AccountID, ref.UploaderID, ref.DocumentID}
	for i, id := range ids {
		parsed, err := uuid.Parse(id)
		if err != nil || parsed == uuid.Nil || parsed.String() != id {
			return "", records.DocumentProcessorError{Code: "storage_unavailable"}
		}
		ids[i] = parsed.String()
	}
	name := "original"
	if ref.Location == "unlocked" {
		if decoded, err := hex.DecodeString(ref.SHA256); err != nil || len(decoded) != 32 || strings.ToLower(ref.SHA256) != ref.SHA256 {
			return "", records.DocumentProcessorError{Code: "storage_unavailable"}
		}
		name = "unlocked-" + ref.SHA256
	}
	return path.Join(ids[0], ids[1], ids[2], name), nil
}
func syncDirectory(root *os.Root, name string) error {
	f, err := root.Open(name)
	if err != nil {
		return err
	}
	return errors.Join(f.Sync(), f.Close())
}
func directories(root *os.Root, name string) error {
	parent := "."
	for _, piece := range strings.Split(path.Dir(name), "/") {
		current := path.Join(parent, piece)
		err := root.Mkdir(current, 0700)
		if err != nil && !errors.Is(err, fs.ErrExist) {
			return err
		}
		info, err := root.Lstat(current)
		if err != nil {
			return err
		}
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm()&0077 != 0 || !owned(info) {
			return errors.New("unsafe storage directory")
		}
		if err = syncDirectory(root, parent); err != nil {
			return err
		}
		parent = current
	}
	return syncDirectory(root, parent)
}

type documentFileSystemContextReader struct {
	ctx    context.Context
	reader io.Reader
}

func (r documentFileSystemContextReader) Read(buffer []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.reader.Read(buffer)
}
func mediaType(prefix []byte) string {
	switch {
	case bytes.HasPrefix(prefix, []byte{137, 80, 78, 71, 13, 10, 26, 10}):
		return "image/png"
	case bytes.HasPrefix(prefix, []byte{255, 216, 255}):
		return "image/jpeg"
	case bytes.HasPrefix(prefix, []byte("%PDF-")):
		return "application/pdf"
	}
	return ""
}
func displayName(name string) string {
	name = strings.TrimSpace(strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || r == '/' || r == '\\' || r == utf8.RuneError {
			return '_'
		}
		return r
	}, name))
	for len(name) > 255 {
		_, size := utf8.DecodeLastRuneInString(name)
		name = name[:len(name)-size]
	}
	if name == "" || name == "." || name == ".." {
		return "document"
	}
	return name
}
func (source *DocumentFileSystemDataSource) Stage(ctx context.Context, ref records.DocumentContentReference, filename string, reader io.Reader) (records.DocumentContentReference, error) {
	name, err := relative(ref)
	if err != nil {
		return ref, err
	}
	if err = ctx.Err(); err != nil {
		return ref, err
	}
	if err = directories(source.ingestion, name); err != nil {
		return ref, storageError(err)
	}
	file, err := source.ingestion.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return ref, storageError(err)
	}
	closed := false
	defer func() {
		if !closed {
			_ = file.Close()
		}
	}()
	limited := io.LimitReader(documentFileSystemContextReader{ctx, reader}, maxFileBytes+1)
	prefix := make([]byte, 512)
	n, err := io.ReadFull(limited, prefix)
	if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
		return ref, storageError(err)
	}
	prefix = prefix[:n]
	detected := mediaType(prefix)
	hash := sha256.New()
	writer := io.MultiWriter(file, hash)
	if _, err = writer.Write(prefix); err != nil {
		return ref, storageError(err)
	}
	remaining, err := io.CopyBuffer(writer, limited, make([]byte, 64<<10))
	if err != nil {
		return ref, storageError(err)
	}
	total := int64(n) + remaining
	if total > maxFileBytes {
		return ref, records.DocumentProcessorError{Code: "too_large"}
	}
	if detected == "" {
		candidate, err := source.ingestion.Open(name)
		if err != nil {
			return ref, storageError(err)
		}
		validation := mimecontent.Validate(candidate)
		_ = candidate.Close()
		if validation != nil {
			return ref, records.DocumentProcessorError{Code: "unsupported_media"}
		}
		detected = "message/rfc822"
	}
	if err = ctx.Err(); err != nil {
		return ref, err
	}
	if err = file.Sync(); err != nil {
		return ref, storageError(err)
	}
	err = file.Close()
	closed = true
	if err != nil {
		return ref, storageError(err)
	}
	if err = syncDirectory(source.ingestion, path.Dir(name)); err != nil {
		return ref, storageError(err)
	}
	ref.Location = "staged"
	ref.MediaType = detected
	ref.Size = total
	ref.SHA256 = hex.EncodeToString(hash.Sum(nil))
	ref.OriginalFilename = displayName(filename)
	ref.IngestedAt = time.Now().UTC()
	return ref, nil
}
func validateFile(file *os.File, ref records.DocumentContentReference, hash bool, ctx context.Context) error {
	info, err := file.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Size() != ref.Size || ref.Size < 1 || ref.Size > maxFileBytes {
		return errors.New("invalid original size")
	}
	if hash {
		digest := sha256.New()
		if _, err = io.Copy(digest, documentFileSystemContextReader{ctx, file}); err != nil {
			return err
		}
		if hex.EncodeToString(digest.Sum(nil)) != ref.SHA256 {
			return errors.New("invalid original digest")
		}
		_, err = file.Seek(0, io.SeekStart)
	}
	return err
}
func (source *DocumentFileSystemDataSource) Open(ctx context.Context, ref records.DocumentContentReference) (io.ReadCloser, error) {
	name, err := relative(ref)
	if err != nil {
		return nil, err
	}
	if err = ctx.Err(); err != nil {
		return nil, err
	}
	first, second := source.ingestion, source.final
	if ref.Location == "final" || ref.Location == "unlocked" {
		first, second = second, first
	} else if ref.Location != "staged" {
		return nil, records.DocumentProcessorError{Code: "storage_unavailable"}
	}
	file, err := first.Open(name)
	fallback := false
	if errors.Is(err, fs.ErrNotExist) && ref.Location != "unlocked" {
		file, err = second.Open(name)
		fallback = true
	}
	if err != nil {
		return nil, storageError(err)
	}
	if err = validateFile(file, ref, fallback, ctx); err != nil {
		file.Close()
		return nil, storageError(err)
	}
	return file, nil
}
func (source *DocumentFileSystemDataSource) Promote(ctx context.Context, ref records.DocumentContentReference) (records.DocumentContentReference, error) {
	name, err := relative(ref)
	if err != nil {
		return ref, err
	}
	if len(ref.SHA256) != 64 {
		return ref, records.DocumentProcessorError{Code: "storage_unavailable"}
	}
	if err = directories(source.final, name); err != nil {
		return ref, storageError(err)
	}
	existing, err := source.final.Open(name)
	if err == nil {
		verified := validateFile(existing, ref, true, ctx)
		closeErr := existing.Close()
		if err = errors.Join(verified, closeErr); err != nil {
			return ref, storageError(err)
		}
		ref.Location = "final"
		return ref, nil
	}
	if !errors.Is(err, fs.ErrNotExist) {
		return ref, storageError(err)
	}
	original, err := source.Open(ctx, ref)
	if err != nil {
		return ref, err
	}
	defer original.Close()
	temporary := name + "." + uuid.NewString() + ".tmp"
	output, err := source.final.OpenFile(temporary, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return ref, storageError(err)
	}
	defer func() { _ = output.Close(); _ = source.final.Remove(temporary) }()
	digest := sha256.New()
	size, err := io.CopyBuffer(io.MultiWriter(output, digest), io.LimitReader(documentFileSystemContextReader{ctx, original}, maxFileBytes+1), make([]byte, 64<<10))
	if err != nil || size != ref.Size || hex.EncodeToString(digest.Sum(nil)) != ref.SHA256 {
		return ref, records.DocumentProcessorError{Code: "storage_unavailable"}
	}
	if err = output.Sync(); err != nil {
		return ref, storageError(err)
	}
	if err = output.Close(); err != nil {
		return ref, storageError(err)
	}
	if err = ctx.Err(); err != nil {
		return ref, err
	}
	if err = source.final.Rename(temporary, name); err != nil {
		return ref, storageError(err)
	}
	if err = syncDirectory(source.final, path.Dir(name)); err != nil {
		return ref, storageError(err)
	}
	ref.Location = "final"
	return ref, nil
}
func (source *DocumentFileSystemDataSource) Remove(ctx context.Context, ref records.DocumentContentReference) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	name, err := relative(ref)
	if err != nil {
		return err
	}
	root := source.ingestion
	if ref.Location == "final" || ref.Location == "unlocked" {
		root = source.final
	} else if ref.Location != "staged" {
		return records.DocumentProcessorError{Code: "storage_unavailable"}
	}
	err = root.Remove(name)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return storageError(err)
	}
	if err == nil {
		if err = syncDirectory(root, path.Dir(name)); err != nil {
			return storageError(err)
		}
	}
	if ref.Location != "staged" {
		return source.removeUnlockedCandidates(ctx, path.Dir(name))
	}
	directory, err := source.final.Open(path.Dir(name))
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return storageError(err)
	}
	defer directory.Close()
	for {
		entries, readErr := directory.ReadDir(100)
		for _, entry := range entries {
			if err = ctx.Err(); err != nil {
				return err
			}
			if strings.HasPrefix(entry.Name(), "original.") && strings.HasSuffix(entry.Name(), ".tmp") {
				if err = source.final.Remove(path.Join(path.Dir(name), entry.Name())); err != nil && !errors.Is(err, fs.ErrNotExist) {
					return storageError(err)
				}
			}
		}
		if errors.Is(readErr, io.EOF) {
			break
		}
		if readErr != nil {
			return storageError(readErr)
		}
	}
	return storageError(directory.Sync())
}
func (source *DocumentFileSystemDataSource) Ready(ctx context.Context) error {
	for _, root := range []*os.Root{source.ingestion, source.final} {
		if err := ctx.Err(); err != nil {
			return err
		}
		name := ".ready-" + uuid.NewString()
		file, err := root.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			return storageError(err)
		}
		writeErr := file.Sync()
		closeErr := file.Close()
		removeErr := root.Remove(name)
		if err = errors.Join(writeErr, closeErr, removeErr, syncDirectory(root, ".")); err != nil {
			return storageError(err)
		}
	}
	return nil
}
