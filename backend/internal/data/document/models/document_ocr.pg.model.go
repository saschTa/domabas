package models

type DocumentOCRRecord struct {
	Status, SemanticIndexing string
	Revision                 int64
	Text, Origin, Reason     *string
}

type DocumentCleanupRecord struct {
	AccountID, UploaderID, DocumentID, LeaseToken string
	Attempts                                      int
}
