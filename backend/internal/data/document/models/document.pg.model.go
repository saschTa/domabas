package models

type DocumentRecords struct {
	Items      []DocumentRecord
	Total      int64
	NextCursor string
}
