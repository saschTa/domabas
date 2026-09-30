package models

func (q EmailRunQuery) Validate() error {
	if q.Limit < 1 || q.Limit > 50 || len(q.Cursor) > 4096 {
		return EmailValidationError{Message: "invalid run pagination"}
	}
	switch q.Status {
	case "", "queued", "running", "succeeded", "partial", "failed", "superseded", "cancelled":
		return nil
	default:
		return EmailValidationError{Message: "invalid run status"}
	}
}
