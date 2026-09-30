package security

import (
	"context"
	"encoding/base64"
	"errors"
	"strings"

	"github.com/alexedwards/argon2id"
)

const dummyHash = "$argon2id$v=19$m=65536,t=3,p=4$+VTM62nkYxbLQzz/bAA+Kw$T3lkR2op5czqFCOwhhif/HYMnGV4ggmgc5I2L7cUIYA"

type Argon2IdentityPasswords struct{ permits chan struct{} }

func NewArgon2IdentityPasswords() *Argon2IdentityPasswords {
	return &Argon2IdentityPasswords{permits: make(chan struct{}, 2)}
}
func (p *Argon2IdentityPasswords) acquire(ctx context.Context) error {
	select {
	case p.permits <- struct{}{}:
		if err := ctx.Err(); err != nil {
			<-p.permits
			return err
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
func (p *Argon2IdentityPasswords) Hash(ctx context.Context, password string) (string, error) {
	if err := p.acquire(ctx); err != nil {
		return "", err
	}
	defer func() { <-p.permits }()
	return argon2id.CreateHash(password, &argon2id.Params{Memory: 65536, Iterations: 3, Parallelism: 4, SaltLength: 16, KeyLength: 32})
}
func (p *Argon2IdentityPasswords) Verify(ctx context.Context, password, hash string) (bool, error) {
	if !validHash(hash) {
		return false, errors.New("stored credential format is invalid")
	}
	if err := p.acquire(ctx); err != nil {
		return false, err
	}
	defer func() { <-p.permits }()
	return argon2id.ComparePasswordAndHash(password, hash)
}
func (p *Argon2IdentityPasswords) Dummy(ctx context.Context, password string) error {
	_, err := p.Verify(ctx, password, dummyHash)
	return err
}
func validHash(hash string) bool {
	if len(hash) > 200 {
		return false
	}
	parts := strings.Split(hash, "$")
	if len(parts) != 6 || parts[0] != "" || parts[1] != "argon2id" || parts[2] != "v=19" || parts[3] != "m=65536,t=3,p=4" {
		return false
	}
	salt, e1 := base64.RawStdEncoding.DecodeString(parts[4])
	key, e2 := base64.RawStdEncoding.DecodeString(parts[5])
	return e1 == nil && e2 == nil && len(salt) == 16 && len(key) == 32 && base64.RawStdEncoding.EncodeToString(salt) == parts[4] && base64.RawStdEncoding.EncodeToString(key) == parts[5]
}
