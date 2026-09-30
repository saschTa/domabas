package repos

import (
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func documentPropertyMetadataMapper(record r.DocumentRecord) m.DocumentMetadata {
	return m.DocumentMetadata{Title: record.Title, Description: record.Description, Kind: record.Kind, Tags: record.Tags, Sender: record.Sender, Recipients: record.Recipients, CC: record.CC, BCC: record.BCC, DocumentDate: record.DocumentDate, Subject: record.Subject, MessageID: record.MessageID}
}
