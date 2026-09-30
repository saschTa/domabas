package models

type DocumentVocabularyRecord struct {
	ComparisonKey, Value string
}

type DocumentVocabularyRecords struct {
	Items      []DocumentVocabularyRecord
	NextCursor string
}
