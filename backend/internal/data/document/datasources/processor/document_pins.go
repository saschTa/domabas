package processor

import models "github.com/domabas/domabas/backend/internal/domain/document/models"

const ModelName = "nomic-embed-text:v1.5"
const ModelDigest = "0a109f422b47e3a30ba2b10eca18548e944e8a23073ee3f3e947efcf3c45e59f"
const Dimensions = 768
const EngineVersion = "5.5.3"
const MaxFileBytes = models.MaxFileBytes
const MaxTextBytes = models.MaxOCRBytes
const MaxRPCBytes = 16 << 20
const weightBase = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/65727574dfcd264acbb0c3e07860e4e9e9b22185/"

func weightArtifacts() []documentProcessorArtifact {
	return []documentProcessorArtifact{
		{"eng.traineddata", 4113088, "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2"},
		{"deu.traineddata", 1525436, "19d219bbb6672c869d20a9636c6816a81eb9a71796cb93ebe0cb1530e2cdb22d"},
		{"osd.traineddata", 10562727, "9cf5d576fcc47564f11265841e5ca839001e7e6f38ff7f7aacf46d15a96b00ff"},
	}
}
func modelArtifacts() []documentProcessorArtifact {
	return []documentProcessorArtifact{
		{"blobs/sha256-31df23ea7daa448f9ccdbbcecce6c14689c8552222b80defd3830707c0139d4f", 420, "31df23ea7daa448f9ccdbbcecce6c14689c8552222b80defd3830707c0139d4f"},
		{"blobs/sha256-970aa74c0a90ef7482477cf803618e776e173c007bf957f635f1015bfcfef0e6", 274290656, "970aa74c0a90ef7482477cf803618e776e173c007bf957f635f1015bfcfef0e6"},
		{"blobs/sha256-c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4", 11357, "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4"},
		{"blobs/sha256-ce4a164fc04605703b485251fe9f1a181688ba0eb6badb80cc6335c0de17ca0d", 17, "ce4a164fc04605703b485251fe9f1a181688ba0eb6badb80cc6335c0de17ca0d"},
	}
}

const ExtractionRevision = "tesseract-pdf-image-v1"
const CurrentExtractionRevision = "document-content-v2"
const EmbeddingInputRevision = "nomic-search-prefix-v1"
const IndexingRevision = "normalized-cosine-v1"
