package processor

import models "github.com/domabas/domabas/backend/internal/domain/document/models"

const ModelName = "nomic-embed-text:v1.5"
const ModelDigest = models.EmbeddingDigest
const modelSize int64 = 274290560
const Dimensions = models.EmbeddingDimensions
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

const ExtractionRevision = "tesseract-pdf-image-v1"
const CurrentExtractionRevision = "document-content-v2"
const EmbeddingInputRevision = "nomic-search-prefix-v1"
const IndexingRevision = "normalized-cosine-v1"
