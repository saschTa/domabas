package models

type DocumentOCR struct {
	Status, SemanticIndexing string
	Revision                 int64
	Text, Origin, Reason     *string
}

type DocumentOCRCorrection struct {
	Revision int64
	Text     string
}

type DocumentCleanupLease struct {
	AccountID, UploaderID, DocumentID, LeaseToken string
	Attempts                                      int
}
