package models

import "errors"

var (
	ErrUnauthorized = errors.New("chat authentication required")
	ErrForbidden    = errors.New("chat permission denied")
	ErrNotFound     = errors.New("chat resource unavailable")
	ErrConflict     = errors.New("chat state conflict")
	ErrBusy         = errors.New("chat capacity exhausted")
	ErrDisabled     = errors.New("chat is disabled")
	ErrCancelled    = errors.New("chat turn stopped")
)

type ChatValidationError struct{ Message string }

func (e ChatValidationError) Error() string { return e.Message }

type ChatProcessingError struct {
	Code      string
	Retryable bool
}

func (e ChatProcessingError) Error() string { return e.Code }
