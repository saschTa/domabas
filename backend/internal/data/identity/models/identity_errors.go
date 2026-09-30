package models

import "errors"

var ErrIdentityPasswordChange = errors.New("password change required")
var ErrIdentityStaleFacts = errors.New("identity command facts changed")

var (
	ErrIdentityUnauthorized = errors.New("identity session is invalid")
	ErrIdentityCredentials  = errors.New("identity credentials changed")
	ErrIdentityForbidden    = errors.New("identity owner permission is required")
	ErrIdentityConflict     = errors.New("identity conflict")
	ErrIdentityNotFound     = errors.New("identity not found")
	ErrActivityUnavailable  = errors.New("personal activity membership limit exceeded")
)

var ErrActivityCursor = errors.New("invalid activity cursor")
