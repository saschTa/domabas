package services

import "encoding/json"

func chatToolFeedbackMapper(code string) string {
	guidance := "This document is unavailable. Use other retrieved evidence or state what could not be verified."
	switch code {
	case "repeated_call":
		guidance = "This exact call was already attempted. It was not executed again. Use its earlier result, choose a different short search query, read another returned document, or answer with the evidence available."
	case "unknown_document":
		guidance = "This document ID was not returned by a search in this turn. No document was read. Search with one or two distinctive words from the user's question and copy a documentId from the results."
	case "invalid_offset":
		guidance = "This continuation offset was not returned for this query or document. No tool was executed. Continue only with a returned nextOffset, choose a new query at offset zero, or answer."
	case "error_query":
		guidance = "An error code is not a document search term. No search was executed. Use a distinctive word from the user's question, or answer that the requested evidence could not be found."
	}
	body, _ := json.Marshal(struct {
		Error    string `json:"error"`
		Guidance string `json:"guidance"`
	}{code, guidance + " Never search for an error code or invent a document ID."})
	return string(body)
}
