package models

import (
	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
)

func (r IdentityRegistrationRequest) Validate() error {
	if _, err := domain.ValidateAccountName(r.AccountName); err != nil {
		return err
	}
	email, err := domain.NormalizeEmail(r.Email)
	if err != nil {
		return err
	}
	return domain.ValidatePassword(r.Password, email)
}
func (r IdentityLoginRequest) Validate() error {
	if _, err := domain.NormalizeEmail(r.Email); err != nil {
		return err
	}
	return domain.ValidateCredential(r.Password)
}
func (r IdentityPasswordRequest) Validate(email string) error {
	if err := domain.ValidateCredential(r.CurrentPassword); err != nil {
		return err
	}
	return domain.ValidatePassword(r.NewPassword, email)
}
func (r IdentityCreateMemberRequest) Validate() error {
	if err := validateClaims(r.Claims); err != nil {
		return err
	}
	email, err := domain.NormalizeEmail(r.Email)
	if err != nil {
		return err
	}
	if !domain.ValidRole(domain.IdentityRole(r.Role)) {
		return domain.IdentityValidationError("role is invalid")
	}
	return domain.ValidatePassword(r.Password, email)
}
func (r IdentityUpdateMemberRequest) Validate() error {
	if !domain.ValidRole(domain.IdentityRole(r.Role)) {
		return domain.IdentityValidationError("role is invalid")
	}
	return validateClaims(r.Claims)
}
func validateClaims(values []string) error {
	claims := make([]domain.IdentityPermission, len(values))
	for i, v := range values {
		claims[i] = domain.IdentityPermission(v)
	}
	return domain.ValidateClaims(claims)
}
func (r IdentityInvitationRequest) Validate() error {
	if _, err := domain.NormalizeEmail(r.Email); err != nil {
		return err
	}
	if !domain.ValidRole(domain.IdentityRole(r.Role)) {
		return domain.IdentityValidationError("role is invalid")
	}
	return validateClaims(r.Claims)
}
func (r IdentitySwitchAccountRequest) Validate() error {
	if _, err := uuid.Parse(r.AccountID); err != nil {
		return domain.IdentityValidationError("accountId must be a UUID")
	}
	return nil
}
func (r IdentitySystemRoleRequest) Validate() error {
	if r.Role != "admin" && r.Role != "user" {
		return domain.IdentityValidationError("system role is invalid")
	}
	return nil
}
