package datasources

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/jackc/pgx/v5"
)

func credentialCipher(key string) (cipher.AEAD, error) {
	decoded, err := base64.StdEncoding.DecodeString(key)
	if err != nil || len(decoded) != 32 {
		return nil, errors.New("Paperless credential key must be a base64-encoded 32-byte key")
	}
	block, err := aes.NewCipher(decoded)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

func CredentialKey(ctx context.Context, db *postgres.PostgresDatabase, override, path string) (string, error) {
	var key string
	err := pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='5s'"); err != nil {
			return err
		}
		var singleton bool
		if err := tx.QueryRow(ctx, "SELECT singleton FROM paperless_admission WHERE singleton FOR UPDATE").Scan(&singleton); err != nil {
			return err
		}
		var retained bool
		if err := tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM paperless_runs WHERE encrypted_token IS NOT NULL)").Scan(&retained); err != nil {
			return err
		}
		var err error
		key, err = loadCredentialKey(override, path, !retained)
		if err != nil {
			return err
		}
		vault, err := credentialCipher(key)
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, "SELECT id,account_id,owner_id,encrypted_token FROM paperless_runs WHERE encrypted_token IS NOT NULL")
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id, account, owner string
			var encrypted []byte
			if err := rows.Scan(&id, &account, &owner, &encrypted); err != nil {
				return err
			}
			if len(encrypted) < vault.NonceSize() {
				return errors.New("Paperless retained credentials are invalid; restore the original credential key and database")
			}
			if _, err := vault.Open(nil, encrypted[:vault.NonceSize()], encrypted[vault.NonceSize():], []byte(id+"/"+account+"/"+owner)); err != nil {
				return errors.New("Paperless credential key cannot decrypt retained jobs; restore the original key")
			}
		}
		return rows.Err()
	})
	if err != nil {
		return "", fmt.Errorf("initialize Paperless credentials: %w", err)
	}
	return key, nil
}

func readCredentialKey(path string) (string, error) {
	if err := validateCredentialDirectory(filepath.Dir(path)); err != nil {
		return "", err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() || (runtime.GOOS != "windows" && info.Mode().Perm()&0077 != 0) {
		return "", errors.New("Paperless credential key file must be a private regular file (mode 0600)")
	}
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	opened, err := file.Stat()
	if err != nil {
		return "", err
	}
	if !os.SameFile(info, opened) {
		return "", errors.New("Paperless credential key file changed while opening")
	}
	body, err := io.ReadAll(io.LimitReader(file, 1025))
	if err != nil {
		return "", err
	}
	key := strings.TrimSpace(string(body))
	if _, err := credentialCipher(key); err != nil || len(body) > 1024 {
		return "", errors.New("Paperless credential key file is invalid; restore the original file")
	}
	return key, nil
}

func validateCredentialDirectory(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !info.IsDir() || (runtime.GOOS != "windows" && info.Mode().Perm()&0022 != 0) {
		return errors.New("Paperless credential key directory must be a real directory without group or public write access")
	}
	return nil
}

func loadCredentialKey(override, path string, allowCreate bool) (string, error) {
	if override != "" {
		if _, err := credentialCipher(override); err != nil {
			return "", fmt.Errorf("PAPERLESS_CREDENTIAL_KEY: %w", err)
		}
		return override, nil
	}
	key, err := readCredentialKey(path)
	if err == nil || !errors.Is(err, os.ErrNotExist) {
		return key, err
	}
	if !allowCreate {
		return "", errors.New("Paperless credential key file is missing while encrypted jobs exist; restore the original key")
	}
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0700); err != nil {
		return "", err
	}
	if err := validateCredentialDirectory(directory); err != nil {
		return "", err
	}
	file, err := os.CreateTemp(directory, ".paperless-key-*")
	if err != nil {
		return "", err
	}
	defer os.Remove(file.Name())
	defer file.Close()
	if err := file.Chmod(0600); err != nil {
		return "", err
	}
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	key = base64.StdEncoding.EncodeToString(bytes)
	if _, err := io.WriteString(file, key+"\n"); err != nil {
		return "", err
	}
	if err := file.Sync(); err != nil {
		return "", err
	}
	if err := file.Close(); err != nil {
		return "", err
	}
	if err := os.Link(file.Name(), path); err != nil && !errors.Is(err, os.ErrExist) {
		return "", err
	}
	if runtime.GOOS != "windows" {
		dir, err := os.Open(directory)
		if err != nil {
			return "", err
		}
		err = dir.Sync()
		dir.Close()
		if err != nil {
			return "", err
		}
	}
	return readCredentialKey(path)
}
