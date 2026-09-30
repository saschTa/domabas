package models

import (
	"errors"
	"fmt"
	"net/mail"
	"strings"
	"unicode/utf8"
)

var ErrMembershipDisabled = fmt.Errorf("%w: membership is disabled", ErrUnauthorized)

var (
	ErrUnauthorized        = errors.New("session is invalid")
	ErrCredentials         = errors.New("email or password is incorrect")
	ErrCurrentPassword     = errors.New("current password is incorrect")
	ErrForbidden           = errors.New("permission denied")
	ErrPasswordChange      = errors.New("password change is required")
	ErrConflict            = errors.New("the change conflicts with an existing record or protected ownership or administration")
	ErrNotFound            = errors.New("the requested resource is unavailable")
	ErrActivityUnavailable = errors.New("personal activity is unavailable")
	ErrStaleFacts          = fmt.Errorf("%w: identity command facts changed", ErrConflict)
)

func (e IdentityValidationError) Error() string { return string(e) }

func NormalizeEmail(value string) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	if len(value) > 254 || len(value) < 3 {
		return "", IdentityValidationError("email is invalid")
	}
	for _, r := range value {
		if r > 127 || r <= 32 {
			return "", IdentityValidationError("email is invalid")
		}
	}
	address, err := mail.ParseAddress(value)
	if err != nil || address.Name != "" || address.Address != value {
		return "", IdentityValidationError("email is invalid")
	}
	return value, nil
}
func ValidatePassword(value, email string) error {
	n := utf8.RuneCountInString(value)
	if !utf8.ValidString(value) || n < 8 || n > 128 || len(value) > 512 {
		return IdentityValidationError("password must contain 8 to 128 characters and at most 512 bytes")
	}
	switch strings.ToLower(value) {
	case email, "password", "12345678", "passwordpassword", "123456789012345", "1234567890123456", "correct horse battery staple":
		return IdentityValidationError("choose a less common password")
	}
	return nil
}
func ValidateAccountName(value string) (string, error) {
	value = strings.TrimSpace(value)
	if !utf8.ValidString(value) || utf8.RuneCountInString(value) < 1 || utf8.RuneCountInString(value) > 100 {
		return "", IdentityValidationError("account name must contain 1 to 100 characters")
	}
	return value, nil
}
func ValidRole(role IdentityRole) bool { return role == Admin || role == User || role == Viewer }

func ValidateCredential(value string) error {
	n := utf8.RuneCountInString(value)
	if !utf8.ValidString(value) || n < 1 || n > 128 || len(value) > 512 {
		return IdentityValidationError("password must contain 1 to 128 characters and at most 512 bytes")
	}
	return nil
}
