package models

import "time"

type Document struct {
	Thumbnail                                      *DocumentThumbnail
	ID                                             string
	Title                                          string
	Description                                    string
	CreatedAt                                      time.Time
	Kind, Sender, DocumentDate, Subject, MessageID string
	Tags, Recipients, CC, BCC                      []string
	File                                           *DocumentFile
	Processing                                     *DocumentProcessing
}

type DocumentCreateInput struct {
	Title       string
	Description string
}

type DocumentPageRequest struct {
	Limit  int
	Offset int
	Cursor string
}

type DocumentPage struct {
	Items      []Document
	Total      int64
	NextCursor string
}

type DocumentValidationError struct{ Message string }
