package models

type DocumentCreateRequest struct {
	Title       *string `json:"title"`
	Description *string `json:"description"`
}

type DocumentListRequest struct {
	Limit  *int
	Offset *int
	Cursor *string
}
