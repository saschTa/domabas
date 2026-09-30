package models

type PaperlessSettings struct {
	RetrievalConcurrency int
	Revision             int64
}

type PaperlessSettingsUpdate struct {
	RetrievalConcurrency int
	ExpectedRevision     int64
}

func (s PaperlessSettingsUpdate) Validate() error {
	if s.RetrievalConcurrency < MinRetrievalConcurrency || s.RetrievalConcurrency > MaxRetrievalConcurrency || s.ExpectedRevision < 1 {
		return PaperlessFailure{Code: "invalid_settings"}
	}
	return nil
}
