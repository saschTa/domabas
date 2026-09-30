package models

type DocumentVocabularyInput struct {
	Field, Query, Cursor string
	Limit                int
}

type DocumentVocabularyOption struct {
	Key, Value string
}

type DocumentVocabularyPage struct {
	Items      []DocumentVocabularyOption
	NextCursor string
}
