package models

import "testing"

func TestRetainedExtractionFingerprintAndMediaMatrix(t *testing.T) {
	legacy := DefaultConfiguration()
	legacy.LLM = DocumentLLMConfiguration{}
	legacy.ManifestRevision, legacy.ExtractionRevision = 1, LegacyExtractionRevision
	fingerprint, err := legacy.CanonicalFingerprint()
	if err != nil || fingerprint != "ab28ece7e83347f4eae67fbbf21e410fb09ac3f8c6b1379ad86b2ff59804f552" {
		t.Fatalf("retained identity changed: %s %v", fingerprint, err)
	}
	sparse := legacy
	sparse.ManifestRevision, sparse.ExtractionRevision, sparse.ChunkingRevision, sparse.EmbeddingInputRevision, sparse.IndexingRevision = 0, "", "", "", ""
	if sparse.WithLegacyIdentity().Fingerprint != fingerprint {
		t.Fatal("sparse historical identity changed")
	}
	for _, config := range []DocumentProcessingConfiguration{legacy, sparse, DefaultConfiguration()} {
		for _, media := range []string{"application/pdf", "image/png", "image/jpeg"} {
			identity, err := config.ExtractionIdentity(media)
			if err != nil || identity.Method != "ocr" || len(identity.Weights) != 3 {
				t.Fatalf("retained/current media unsupported: %s %v", media, err)
			}
		}
	}
	if _, err := legacy.ExtractionIdentity("message/rfc822"); err == nil {
		t.Fatal("historical extraction accepted email")
	}
	current := DefaultConfiguration()
	identity, err := current.ExtractionIdentity("message/rfc822")
	if err != nil || identity.Method != "mime" || identity.Engine != "domabas-mime" || len(identity.Weights) != 0 {
		t.Fatalf("email identity %+v %v", identity, err)
	}
	current.ManifestRevision = 1
	if _, err = current.ExtractionIdentity("message/rfc822"); err == nil {
		t.Fatal("invalid manifest/revision pair accepted")
	}
}

func TestExtractionEvidenceRejectsInventedOCRAndDuplicateWeights(t *testing.T) {
	config := DefaultConfiguration()
	result := DocumentExtraction{ExtractionRevision: CurrentExtractionRevision, Text: "Email body", Pages: 1, Engine: "domabas-mime", EngineVersion: "1"}
	if err := config.ValidateExtraction("message/rfc822", result); err != nil {
		t.Fatal(err)
	}
	result.Engine = "tesseract"
	if err := config.ValidateExtraction("message/rfc822", result); err == nil {
		t.Fatal("email credited to OCR")
	}
	result = DocumentExtraction{ExtractionRevision: CurrentExtractionRevision, Text: "Invoice", Pages: 1, Engine: config.Engine, EngineVersion: config.EngineVersion, Weights: append([]DocumentWeight{}, config.Weights...)}
	result.Weights[1] = result.Weights[0]
	if err := config.ValidateExtraction("application/pdf", result); err == nil {
		t.Fatal("duplicate weight evidence accepted")
	}
	result.Weights = config.Weights
	result.Text = "invalid\x00text"
	if err := config.ValidateExtraction("application/pdf", result); err == nil {
		t.Fatal("NUL text accepted")
	}
}
