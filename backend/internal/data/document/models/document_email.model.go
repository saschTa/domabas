package models

import "io"

type DocumentEmailMetadata struct {
	Subject, Sender, MessageID, Date string
	Recipients, CC, BCC              []string
}
type DocumentEmailPart struct {
	Path, Filename, MediaType, Status, FailureCode string
	Reader                                         io.Reader
}
type DocumentEmailInspection struct {
	Metadata        DocumentEmailMetadata
	Text            string
	ContentFailures bool
	TextFailures    bool
}
