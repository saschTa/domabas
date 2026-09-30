package models

type PaperlessStatusProjection struct {
	Completed, FailedItem, Partial string
}

func DefaultPaperlessStatusProjection() PaperlessStatusProjection {
	return PaperlessStatusProjection{Completed: "succeeded", FailedItem: "failed", Partial: "partial"}
}

func ValidatePaperlessRunPage(page PaperlessPageRequest) error {
	if page.Limit < 1 || page.Limit > 100 {
		return PaperlessFailure{Code: "invalid_pagination"}
	}
	switch page.Status {
	case "", "queued", "running", "succeeded", "partial", "failed", "cancelled":
		return nil
	default:
		return PaperlessFailure{Code: "invalid_pagination"}
	}
}
