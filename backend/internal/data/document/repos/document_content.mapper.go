package repos

import (
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func documentContentDomainToRecordMapper(ref domain.DocumentFileReference) records.DocumentContentReference {
	return records.DocumentContentReference{AccountID: ref.AccountID, UploaderID: ref.UploaderID, DocumentID: ref.DocumentID, Location: ref.Location, OriginalFilename: ref.File.OriginalFilename, MediaType: ref.File.MediaType, SHA256: ref.File.SHA256, Size: ref.File.Size, IngestedAt: ref.File.IngestedAt}
}

func documentContentRecordToDomainMapper(ref records.DocumentContentReference) domain.DocumentFileReference {
	return domain.DocumentFileReference{AccountID: ref.AccountID, UploaderID: ref.UploaderID, DocumentID: ref.DocumentID, Location: ref.Location, File: domain.DocumentFile{OriginalFilename: ref.OriginalFilename, MediaType: ref.MediaType, SHA256: ref.SHA256, Size: ref.Size, UploaderID: ref.UploaderID, IngestedAt: ref.IngestedAt}}
}
