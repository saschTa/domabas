package filesystem

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"io/fs"
	"os"
	"path"
	"strings"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/google/uuid"
)

func (source *DocumentFileSystemDataSource) StoreUnlocked(ctx context.Context, ref records.DocumentContentReference, data []byte) (records.DocumentContentReference, error) {
	if len(data) == 0 || int64(len(data)) > maxFileBytes || !bytes.HasPrefix(data, []byte("%PDF-")) {
		return ref, records.DocumentProcessorError{Code: "invalid_file"}
	}
	digest := sha256.Sum256(data)
	ref.SHA256 = hex.EncodeToString(digest[:])
	ref.Size = int64(len(data))
	ref.Location = "unlocked"
	name, err := relative(ref)
	if err != nil {
		return ref, err
	}
	if err = directories(source.final, name); err != nil {
		return ref, storageError(err)
	}
	temporary := path.Join(path.Dir(name), "original."+uuid.NewString()+".tmp")
	output, err := source.final.OpenFile(temporary, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return ref, storageError(err)
	}
	defer func() { _ = output.Close(); _ = source.final.Remove(temporary) }()
	if _, err = io.Copy(output, documentFileSystemContextReader{ctx, bytes.NewReader(data)}); err != nil {
		return ref, storageError(err)
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
	return ref, storageError(syncDirectory(source.final, path.Dir(name)))
}

func (source *DocumentFileSystemDataSource) removeUnlockedCandidates(ctx context.Context, name string) error {
	directory, err := source.final.Open(name)
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
			if err := ctx.Err(); err != nil {
				return err
			}
			if strings.HasPrefix(entry.Name(), "unlocked-") {
				if err = source.final.Remove(path.Join(name, entry.Name())); err != nil && !errors.Is(err, fs.ErrNotExist) {
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
