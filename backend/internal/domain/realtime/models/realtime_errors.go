package models

import "errors"

var (
	ErrUnauthorized = errors.New("realtime session is unavailable")
	ErrForbidden    = errors.New("realtime connect permission is required")
	ErrUnavailable  = errors.New("realtime is unavailable")
)
