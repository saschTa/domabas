package repos

import (
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func documentEmailMetadataMapper(result r.DocumentEmailMetadata) m.DocumentMetadata {
	metadata := m.DocumentMetadata{Title: boundedEmailText(result.Subject, 200, 800), Subject: boundedEmailText(result.Subject, 200, 800), Sender: result.Sender, MessageID: boundedEmailText(result.MessageID, 512, 2048), DocumentDate: result.Date, Kind: "email", Tags: []string{}, Recipients: result.Recipients[:min(len(result.Recipients), 20)], CC: result.CC[:min(len(result.CC), 20)], BCC: result.BCC[:min(len(result.BCC), 20)]}
	if metadata.Title == "" {
		metadata.Title = "Email"
	}
	return metadata
}
