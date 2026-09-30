package repos

import (
	"context"
	"fmt"
	"strings"
	"unicode/utf8"

	r "github.com/domabas/domabas/backend/internal/data/paperless/models"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

func paperlessPreviewDocumentMapper(v r.PaperlessDocumentRecord) m.PaperlessDocument {
	title := v.Title
	if !utf8.ValidString(title) || utf8.RuneCountInString(title) > 1024 || strings.ContainsRune(title, 0) {
		title = fmt.Sprintf("Paperless document %d", v.ID)
	}
	return m.PaperlessDocument{ID: v.ID, Title: title}
}

func (r *PaperlessRepository) metadataMapper(ctx context.Context, c m.PaperlessConnection, v r.PaperlessDocumentRecord) (d.DocumentMetadata, error) {
	fallback, err := (d.DocumentMetadata{
		Title:       fmt.Sprintf("Paperless document %d", v.ID),
		Kind:        "document",
		Description: fmt.Sprintf("Imported from Paperless: %s/documents/%d/details", c.ServerURL, v.ID),
	}).Normalize()
	if err != nil {
		return d.DocumentMetadata{}, m.PaperlessFailure{Code: "invalid_metadata"}
	}
	if len(v.Tags) > 20 {
		return fallback, nil
	}
	metadata := d.DocumentMetadata{Title: v.Title, Kind: "document", DocumentDate: v.Created, Description: fallback.Description}
	if _, err := metadata.Normalize(); err != nil {
		return fallback, nil
	}
	seen := map[string]bool{}
	for _, tag := range v.Tags {
		name, err := r.source.Name(ctx, c, "tags", tag)
		if err != nil {
			return d.DocumentMetadata{}, err
		}
		name = strings.ToLower(strings.TrimSpace(name))
		if !seen[name] {
			metadata.Tags = append(metadata.Tags, name)
			seen[name] = true
		}
	}
	if v.Correspondent != nil {
		metadata.Sender, err = r.source.Name(ctx, c, "correspondents", *v.Correspondent)
		if err != nil {
			return d.DocumentMetadata{}, err
		}
	}
	if v.DocumentType != nil {
		name, err := r.source.Name(ctx, c, "document_types", *v.DocumentType)
		if err != nil {
			return d.DocumentMetadata{}, err
		}
		metadata.Description += "\nDocument type: " + name
	}
	if v.ArchiveSerialNumber != nil {
		metadata.Description += fmt.Sprintf("\nArchive serial number: %d", *v.ArchiveSerialNumber)
	}
	metadata, err = metadata.Normalize()
	if err != nil {
		return fallback, nil
	}
	return metadata, nil
}
