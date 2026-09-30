package models

type PaperlessDocumentRecord struct {
	ID                  int64   `json:"id"`
	Title               string  `json:"title"`
	Created             string  `json:"created"`
	Filename            string  `json:"original_file_name"`
	Tags                []int64 `json:"tags"`
	Correspondent       *int64  `json:"correspondent"`
	DocumentType        *int64  `json:"document_type"`
	ArchiveSerialNumber *int64  `json:"archive_serial_number"`
}
type PaperlessPageRecord struct {
	Count   *int                      `json:"count"`
	Next    *string                   `json:"next"`
	Results []PaperlessDocumentRecord `json:"results"`
}
type PaperlessNamedRecord struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}
