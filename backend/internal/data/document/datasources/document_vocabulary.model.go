package datasources

type documentVocabularyFingerprint struct {
	Version   int    `json:"v"`
	Operation string `json:"operation"`
	Namespace string `json:"namespace"`
	Field     string `json:"field"`
	Query     string `json:"query"`
	Limit     int    `json:"limit"`
}
