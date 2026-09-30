package services

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"time"

	identityinterfaces "github.com/domabas/domabas/backend/internal/domain/identity/interfaces"
	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type IdentityService struct {
	repository identityinterfaces.IdentityRepository
	passwords  identityinterfaces.IdentityPasswords
	authorizer identityinterfaces.IdentityAuthorizer
	now        func() time.Time
	newID      func() string
}

func NewIdentityService(repository identityinterfaces.IdentityRepository, passwords identityinterfaces.IdentityPasswords, authorizer identityinterfaces.IdentityAuthorizer, now func() time.Time, newID func() string) *IdentityService {
	return &IdentityService{repository: repository, passwords: passwords, authorizer: authorizer, now: now, newID: newID}
}
func (s *IdentityService) complete(p identitymodels.IdentityPrincipal) identitymodels.IdentityPrincipal {
	p.Permissions = make([]identitymodels.IdentityPermission, 0, 3)
	for _, claim := range identitymodels.ClaimCatalog() {
		if s.authorizer.Allows(p, claim.ID) {
			p.Permissions = append(p.Permissions, claim.ID)
		}
	}
	return p
}
func (s *IdentityService) newSession() (string, identitymodels.IdentitySessionRecord, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", identitymodels.IdentitySessionRecord{}, err
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	digest := sha256.Sum256(raw)
	now := s.now().UTC().Truncate(time.Microsecond)
	return token, identitymodels.IdentitySessionRecord{Digest: hex.EncodeToString(digest[:]), CreatedAt: now}, nil
}

func (s *IdentityService) RestoreSession(ctx context.Context, token string) (identitymodels.IdentitySession, error) {
	p, err := s.Authenticate(ctx, token)
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	return identitymodels.IdentitySession{Token: token, ExpiresAt: p.SessionExpiresAt, Identity: p}, nil
}
func TokenDigest(token string) (string, error) {
	raw, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(raw) != 32 || base64.RawURLEncoding.EncodeToString(raw) != token {
		return "", identitymodels.ErrUnauthorized
	}
	digest := sha256.Sum256(raw)
	return hex.EncodeToString(digest[:]), nil
}
func (s *IdentityService) cleanup(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	_ = s.repository.CleanupSessions(ctx, s.now())
}
func (s *IdentityService) Register(ctx context.Context, name, email, password string) (identitymodels.IdentitySession, error) {
	name, err := identitymodels.ValidateAccountName(name)
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	email, err = identitymodels.NormalizeEmail(email)
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	if err = identitymodels.ValidatePassword(password, email); err != nil {
		return identitymodels.IdentitySession{}, err
	}
	hash, err := s.passwords.Hash(ctx, password)
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	token, record, err := s.newSession()
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	input := identitymodels.IdentityRegistration{AccountID: s.newID(), UserID: s.newID(), AccountName: name, Email: email, PasswordHash: hash, CreatedAt: record.CreatedAt, Session: record}
	var p identitymodels.IdentityPrincipal
	for attempt := 0; attempt < 3; attempt++ {
		facts, readErr := s.repository.InstallationFacts(ctx)
		if readErr != nil {
			return identitymodels.IdentitySession{}, readErr
		}
		input.ExpectedSetupEligible, input.ConsumeSetup = facts.BootstrapEligible, facts.BootstrapEligible
		input.SystemRole = identitymodels.User
		if facts.BootstrapEligible {
			input.SystemRole = identitymodels.Admin
		}
		p, err = s.repository.Register(ctx, input)
		if !errors.Is(err, identitymodels.ErrStaleFacts) {
			break
		}
	}
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	s.cleanup(ctx)
	return identitymodels.IdentitySession{Token: token, ExpiresAt: record.ExpiresAt, Identity: s.complete(p)}, nil
}
func (s *IdentityService) Login(ctx context.Context, email, password string) (identitymodels.IdentitySession, error) {
	email, err := identitymodels.NormalizeEmail(email)
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	if err = identitymodels.ValidateCredential(password); err != nil {
		return identitymodels.IdentitySession{}, err
	}
	credentials, err := s.repository.CredentialsByEmail(ctx, email)
	if errors.Is(err, identitymodels.ErrNotFound) || err == nil && !credentials.Enabled {
		if err = s.passwords.Dummy(ctx, password); err != nil {
			return identitymodels.IdentitySession{}, err
		}
		return identitymodels.IdentitySession{}, identitymodels.ErrCredentials
	}
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	valid, err := s.passwords.Verify(ctx, password, credentials.PasswordHash)
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	if !valid {
		return identitymodels.IdentitySession{}, identitymodels.ErrCredentials
	}
	token, record, err := s.newSession()
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	p, err := s.repository.CreateSession(ctx, credentials, record)
	if err != nil {
		return identitymodels.IdentitySession{}, err
	}
	s.cleanup(ctx)
	return identitymodels.IdentitySession{Token: token, ExpiresAt: record.ExpiresAt, Identity: s.complete(p)}, nil
}
func (s *IdentityService) Authenticate(ctx context.Context, token string) (identitymodels.IdentityPrincipal, error) {
	digest, err := TokenDigest(token)
	if err != nil {
		return identitymodels.IdentityPrincipal{}, err
	}
	return s.sessionAuthority(ctx, digest)
}
func (s *IdentityService) Logout(ctx context.Context, p identitymodels.IdentityPrincipal) error {
	p, err := s.resolveAuthority(ctx, p, false)
	if err != nil {
		return err
	}
	return s.repository.Logout(ctx, p)
}
func (s *IdentityService) ChangePassword(ctx context.Context, p identitymodels.IdentityPrincipal, current, next string) error {
	p, err := s.resolveAuthority(ctx, p, false)
	if err != nil {
		return err
	}
	if err := identitymodels.ValidatePassword(next, p.Email); err != nil {
		return err
	}
	if len(current) > 512 {
		return identitymodels.ErrCurrentPassword
	}
	credentials, err := s.repository.CredentialsByEmail(ctx, p.Email)
	if err != nil {
		return err
	}
	valid, err := s.passwords.Verify(ctx, current, credentials.PasswordHash)
	if err != nil {
		return err
	}
	if !valid {
		return identitymodels.ErrCurrentPassword
	}
	hash, err := s.passwords.Hash(ctx, next)
	if err != nil {
		return err
	}
	return s.repository.ChangePassword(ctx, p, credentials, hash, s.now())
}
func (s *IdentityService) CreateMember(ctx context.Context, p identitymodels.IdentityPrincipal, email, password string, role identitymodels.IdentityRole, claims []identitymodels.IdentityPermission) (identitymodels.IdentityMember, error) {
	p, err := s.requireAuthority(ctx, p, identitymodels.UsersManage)
	if err != nil {
		return identitymodels.IdentityMember{}, err
	}
	if err := identitymodels.ValidateClaims(claims); err != nil {
		return identitymodels.IdentityMember{}, err
	}
	email, err = identitymodels.NormalizeEmail(email)
	if err != nil {
		return identitymodels.IdentityMember{}, err
	}
	if !identitymodels.ValidRole(role) {
		return identitymodels.IdentityMember{}, identitymodels.IdentityValidationError("role is invalid")
	}
	if !s.canDelegate(p, role, claims) {
		return identitymodels.IdentityMember{}, identitymodels.ErrForbidden
	}
	if err = identitymodels.ValidatePassword(password, email); err != nil {
		return identitymodels.IdentityMember{}, err
	}
	hash, err := s.passwords.Hash(ctx, password)
	if err != nil {
		return identitymodels.IdentityMember{}, err
	}
	accountName := email
	if len(accountName) > 100 {
		accountName = accountName[:100]
	}
	m, err := s.repository.CreateMember(ctx, p, identitymodels.IdentityNewMember{ID: s.newID(), AccountID: s.newID(), Email: email, PersonalAccountName: accountName, PersonalRole: identitymodels.Admin, PersonalOwner: true, PasswordHash: hash, Role: role, Claims: claims, CreatedAt: s.now()}, s.now())
	return s.completeMember(m), err
}
func (s *IdentityService) UpdateMember(ctx context.Context, p identitymodels.IdentityPrincipal, id string, role identitymodels.IdentityRole, claims []identitymodels.IdentityPermission, enabled bool) (identitymodels.IdentityMember, error) {
	p, err := s.requireAuthority(ctx, p, identitymodels.UsersManage)
	if err != nil {
		return identitymodels.IdentityMember{}, err
	}
	if err := identitymodels.ValidateClaims(claims); err != nil {
		return identitymodels.IdentityMember{}, err
	}
	if !identitymodels.ValidRole(role) {
		return identitymodels.IdentityMember{}, identitymodels.IdentityValidationError("role is invalid")
	}
	if !s.canDelegate(p, role, claims) {
		return identitymodels.IdentityMember{}, identitymodels.ErrForbidden
	}
	expected, err := s.repository.MemberFacts(ctx, p.AccountID, id)
	if err != nil {
		return identitymodels.IdentityMember{}, err
	}
	if expected.IsOwner {
		return identitymodels.IdentityMember{}, identitymodels.ErrConflict
	}
	m, err := s.repository.UpdateMember(ctx, p, expected, role, claims, enabled, s.now())
	return s.completeMember(m), err
}
func (s *IdentityService) ListMembers(ctx context.Context, p identitymodels.IdentityPrincipal, limit, offset int) (identitymodels.IdentityMemberPage, error) {
	p, err := s.requireAuthority(ctx, p, identitymodels.UsersManage)
	if err != nil {
		return identitymodels.IdentityMemberPage{}, err
	}
	if limit < 1 || limit > 100 || offset < 0 {
		return identitymodels.IdentityMemberPage{}, identitymodels.IdentityValidationError("pagination is invalid")
	}
	page, err := s.repository.ListMembers(ctx, p, limit, offset, s.now())
	for i := range page.Items {
		page.Items[i] = s.completeMember(page.Items[i])
	}
	return page, err
}
