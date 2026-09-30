package models

type DocumentOCRRequest struct {
	Revision int64  `json:"revision"`
	Text     string `json:"text"`
}
