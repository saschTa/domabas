package models

import (
	"errors"
	"math"
	"slices"
	"time"
)

func PlanDocumentProcessing(work DocumentProcessingWork, requested string) (DocumentProcessingCommand, error) {
	command := DocumentProcessingCommand{Expected: work, State: "processing", Stage: work.Stage, Deadline: 15 * time.Minute, Unlimited: work.UnlimitedInference}
	if !slices.Contains([]string{"extracting", "enriching", "embedding", "finalizing"}, requested) {
		return command, ErrStaleJob
	}
	if requested == "finalizing" && work.State == "ready" && work.Stage == "complete" {
		command.Replay = true
		return command, nil
	}
	if !work.Eligible {
		return command, ErrStaleJob
	}
	if work.Stage == "queued" {
		if requested != "extracting" {
			return command, ErrStaleJob
		}
		command.Stage = "extracting"
	}
	return command, nil
}

func PlanDocumentExtraction(work DocumentProcessingWork, revision int64, extraction DocumentExtraction) (DocumentExtractionCommand, error) {
	command := DocumentExtractionCommand{Expected: work, Extraction: extraction, Revision: revision, ReplayStages: []string{"invoicing", "enriching", "embedding", "finalizing"}}
	if extraction.InvoiceFailureCode != "" && extraction.InvoiceFailureCode != "invalid_invoice" {
		return command, DocumentProcessingError{Code: "processing_failed"}
	}
	if len(extraction.InvoiceXML) > 2<<20 {
		return command, DocumentProcessingError{Code: "resource_limit"}
	}
	chunks, err := processingChunks(extraction.Text)
	if err != nil {
		return command, err
	}
	if !work.Eligible {
		return command, ErrStaleJob
	}
	if slices.Contains(command.ReplayStages, work.Stage) {
		return command, nil
	}
	if work.Stage != "extracting" || work.Revision != revision {
		return command, ErrStaleJob
	}
	command.Identity, err = work.Configuration.ExtractionIdentity(work.Reference.File.MediaType)
	if err != nil {
		return command, err
	}
	if work.ManualText != nil {
		chunks, err = processingChunks(*work.ManualText)
		if err != nil {
			return command, err
		}
	} else {
		if revision == math.MaxInt64 {
			return command, DocumentProcessingError{Code: "resource_limit"}
		}
		command.Revision++
	}
	command.Chunks = chunks
	command.Stage = "embedding"
	if len(chunks) == 0 {
		command.Stage = "finalizing"
	}
	if !work.SplitPipeline && extraction.InvoiceFailureCode != "" {
		return command, DocumentProcessingError{Code: extraction.InvoiceFailureCode}
	}
	if !work.SplitPipeline && work.Configuration.LLM.Enabled && len(chunks) > 0 {
		command.Stage = "enriching"
	}
	return command, nil
}

func PlanDocumentEmbeddings(work DocumentProcessingWork, revision int64, space DocumentEmbeddingSpace, chunks []DocumentChunk) (DocumentEmbeddingCommand, error) {
	command := DocumentEmbeddingCommand{Expected: work, Stage: "finalizing", ReplayStages: []string{"finalizing"}}
	if len(chunks) == 0 || len(chunks) > MaxOCRChunks {
		return command, DocumentProcessingError{Code: "resource_limit"}
	}
	command.Chunks = make([]DocumentChunk, len(chunks))
	for i, chunk := range chunks {
		normalized, err := NormalizeVector(chunk.Vector)
		if err != nil {
			return command, err
		}
		chunk.Vector = normalized
		command.Chunks[i] = chunk
	}
	if !work.Eligible || work.Revision != revision {
		return command, ErrStaleJob
	}
	if work.Configuration.EmbeddingSpace() != space {
		return command, DocumentProcessingError{Code: "configuration_unavailable"}
	}
	if work.Stage != "embedding" && work.Stage != "finalizing" {
		return command, ErrStaleJob
	}
	return command, nil
}

func PlanDocumentPublication(work DocumentProcessingWork, revision int64) (DocumentPublicationCommand, error) {
	command := DocumentPublicationCommand{Expected: work, State: "ready", Stage: "complete", Location: "final", Digest: work.Configuration.EmbeddingDigest}
	if !work.Eligible || work.Stage != "finalizing" || work.Revision != revision || !work.EmbeddingsComplete {
		return command, ErrStaleJob
	}
	return command, nil
}

func processingChunks(text string) ([]DocumentChunk, error) {
	chunks, err := OCRChunks(text)
	if errors.Is(err, ErrTooLarge) {
		return nil, DocumentProcessingError{Code: "resource_limit"}
	}
	if err != nil {
		return nil, DocumentProcessingError{Code: "processing_failed"}
	}
	return chunks, nil
}
