package models

import (
	"errors"
	"time"
)

func DocumentThumbnailFailure(err error) DocumentThumbnailOutcome {
	if err == nil {
		return DocumentThumbnailOutcome{}
	}
	if errors.Is(err, ErrStaleJob) || errors.Is(err, ErrNotFound) {
		return DocumentThumbnailOutcome{FailureCode: "obsolete"}
	}
	var failure DocumentProcessingError
	if errors.As(err, &failure) {
		return DocumentThumbnailOutcome{FailureCode: failure.Code, Retryable: failure.Retryable}
	}
	if errors.Is(err, ErrUnsupportedMedia) || errors.Is(err, ErrTooLarge) {
		return DocumentThumbnailOutcome{FailureCode: "unsupported_media"}
	}
	return DocumentThumbnailOutcome{FailureCode: "thumbnail_unavailable", Retryable: true}
}

func DocumentThumbnailRetryDelay(attempt int) time.Duration {
	return min(time.Hour, time.Minute*time.Duration(1<<min(max(attempt-1, 0), 6)))
}
func DocumentThumbnailCompletion(outcome DocumentThumbnailOutcome) DocumentThumbnailOutcome {
	outcome.Status = "failed"
	if outcome.FailureCode == "obsolete" {
		outcome.Status = "obsolete"
	}
	return outcome
}
