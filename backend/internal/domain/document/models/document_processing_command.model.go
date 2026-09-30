package models

import "time"

type DocumentProcessingCommand struct {
	Expected          DocumentProcessingWork
	State, Stage      string
	Deadline          time.Duration
	Unlimited, Replay bool
}
type DocumentExtractionCommand struct {
	Expected     DocumentProcessingWork
	Extraction   DocumentExtraction
	Identity     DocumentExtractionIdentity
	Revision     int64
	Chunks       []DocumentChunk
	Stage        string
	ReplayStages []string
}
type DocumentEmbeddingCommand struct {
	Expected     DocumentProcessingWork
	Chunks       []DocumentChunk
	Stage        string
	ReplayStages []string
}
type DocumentPublicationCommand struct {
	Expected                       DocumentProcessingWork
	State, Stage, Location, Digest string
	Replay                         bool
}
