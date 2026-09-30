package services

import (
	"context"
	"encoding/base64"
	"errors"
	"testing"
	"time"

	identityinterfaces "github.com/domabas/domabas/backend/internal/domain/identity/interfaces"
	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type credentialRepository struct {
	identityinterfaces.IdentityRepository
	credentials                     identitymodels.IdentityCredentials
	err                             error
	sessionCalls, authenticateCalls int
}

func (r *credentialRepository) CredentialsByEmail(context.Context, string) (identitymodels.IdentityCredentials, error) {
	return r.credentials, r.err
}
func (r *credentialRepository) CreateSession(context.Context, identitymodels.IdentityCredentials, identitymodels.IdentitySessionRecord) (identitymodels.IdentityPrincipal, error) {
	r.sessionCalls++
	return identitymodels.IdentityPrincipal{}, nil
}
func (r *credentialRepository) SessionAuthority(context.Context, string) (identitymodels.IdentityAuthorityFacts, error) {
	r.authenticateCalls++
	return identitymodels.IdentityAuthorityFacts{}, identitymodels.ErrUnauthorized
}

type passwordSpy struct{ verify, dummy, hash int }

func (p *passwordSpy) Hash(context.Context, string) (string, error) { p.hash++; return "hash", nil }
func (p *passwordSpy) Verify(context.Context, string, string) (bool, error) {
	p.verify++
	return false, nil
}
func (p *passwordSpy) Dummy(context.Context, string) error { p.dummy++; return nil }

type denyAuthorization struct{}

func (denyAuthorization) Allows(identitymodels.IdentityPrincipal, identitymodels.IdentityPermission) bool {
	return false
}
func TestWrongUnknownAndDisabledCredentialsHaveEquivalentBoundedWork(t *testing.T) {
	for _, test := range []struct {
		name          string
		record        identitymodels.IdentityCredentials
		err           error
		verify, dummy int
	}{{"unknown", identitymodels.IdentityCredentials{}, identitymodels.ErrNotFound, 0, 1}, {"disabled", identitymodels.IdentityCredentials{Enabled: false}, nil, 0, 1}, {"wrong", identitymodels.IdentityCredentials{Enabled: true, PasswordHash: "hash"}, nil, 1, 0}} {
		t.Run(test.name, func(t *testing.T) {
			repository := &credentialRepository{credentials: test.record, err: test.err}
			passwords := &passwordSpy{}
			service := NewIdentityService(repository, passwords, denyAuthorization{}, time.Now, func() string { return "id" })
			if _, err := service.Login(t.Context(), "user@example.test", "x"); !errors.Is(err, identitymodels.ErrCredentials) {
				t.Fatalf("failure=%v", err)
			}
			if passwords.verify != test.verify || passwords.dummy != test.dummy || repository.sessionCalls != 0 {
				t.Fatalf("work=%+v sessions=%d", passwords, repository.sessionCalls)
			}
		})
	}
}
func TestTokensMustBeCanonical32ByteBase64URL(t *testing.T) {
	repository := &credentialRepository{}
	service := NewIdentityService(repository, &passwordSpy{}, denyAuthorization{}, time.Now, func() string { return "id" })
	canonical := base64.RawURLEncoding.EncodeToString(make([]byte, 32))
	for _, token := range []string{"", canonical + "=", canonical[:42], canonical + "A", canonical[:42] + "B", "not a token"} {
		if _, err := service.Authenticate(t.Context(), token); !errors.Is(err, identitymodels.ErrUnauthorized) {
			t.Errorf("malformed token accepted %q: %v", token, err)
		}
	}
	if repository.authenticateCalls != 0 {
		t.Fatal("malformed tokens reached storage")
	}
	if _, err := service.Authenticate(t.Context(), canonical); !errors.Is(err, identitymodels.ErrUnauthorized) || repository.authenticateCalls != 1 {
		t.Fatalf("canonical token lookup %v calls%d", err, repository.authenticateCalls)
	}
}
