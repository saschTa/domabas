package services

import (
	"context"
	"errors"
	"testing"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type documentAIRetryConflictRepository struct {
	p.DocumentIngestionRepository
	reads, writes int
	actor         m.DocumentActor
}

func (r *documentAIRetryConflictRepository) AIRetryFacts(context.Context, m.DocumentActor, string, string) (m.DocumentAIRetryFacts, error) {
	r.reads++
	if r.reads == 1 {
		return m.DocumentAIRetryFacts{Configuration: m.DocumentProcessingConfiguration{Revision: 4}, Enqueue: m.DocumentAIEnqueueFacts{State: "ready"}}, nil
	}
	return m.DocumentAIRetryFacts{RequestExists: true, RequestAccount: r.actor.AccountID, RequestOwner: r.actor.UserID, RequestDocument: "doc", RequestRevision: 4, Existing: m.DocumentAIProcessing{JobID: "winner", Attempt: 2}}, nil
}
func (r *documentAIRetryConflictRepository) RetryAI(context.Context, m.DocumentActor, string, m.DocumentAIRetryCommand) (m.DocumentAIProcessing, error) {
	r.writes++
	return m.DocumentAIProcessing{}, m.ErrConflict
}

func TestDocumentAIRetryResolvesConcurrentIdenticalRequest(t *testing.T) {
	repo := &documentAIRetryConflictRepository{actor: m.DocumentActor{AccountID: "account", UserID: "user"}}
	service := NewDocumentIngestionService(repo, nil, nil, documentAllowedAuthority(), nil)
	result, err := service.RetryAI(t.Context(), repo.actor, "doc", m.DocumentReindexRequest{RequestID: "11111111-1111-4111-8111-111111111111", ConfigurationRevision: 4})
	if err != nil || result.JobID != "winner" || repo.reads != 2 || repo.writes != 1 {
		t.Fatalf("retry %+v reads=%d writes=%d: %v", result, repo.reads, repo.writes, err)
	}
}

type documentCorrectionConflictRepository struct {
	p.DocumentIngestionRepository
	reads, writes   int
	revisionChanged bool
}

func (r *documentCorrectionConflictRepository) CorrectionFacts(context.Context, m.DocumentActor, string) (m.DocumentCorrectionFacts, error) {
	r.reads++
	facts := m.DocumentCorrectionFacts{Revision: 4, Generation: 1, Location: "staged"}
	if r.reads > 1 {
		facts.Location = "final"
		if r.revisionChanged {
			facts.Revision++
		}
	}
	return facts, nil
}
func (r *documentCorrectionConflictRepository) CorrectOCR(_ context.Context, _ m.DocumentActor, _ string, command m.DocumentCorrectionCommand) (m.DocumentOCR, error) {
	r.writes++
	if r.writes == 1 {
		return m.DocumentOCR{}, m.ErrConflict
	}
	if command.Expected.Revision != 4 || command.Expected.Location != "final" {
		return m.DocumentOCR{}, errors.New("replan lost expected correction")
	}
	return m.DocumentOCR{}, nil
}
func TestDocumentCorrectionReplansPublicationButKeepsCallerRevision(t *testing.T) {
	for _, changed := range []bool{false, true} {
		repo := &documentCorrectionConflictRepository{revisionChanged: changed}
		service := NewDocumentIngestionService(repo, nil, nil, documentAllowedAuthority(), nil)
		_, err := service.CorrectOCR(t.Context(), m.DocumentActor{}, "doc", m.DocumentOCRCorrection{Revision: 4, Text: ""})
		if changed {
			if !errors.Is(err, m.ErrConflict) || repo.writes != 1 {
				t.Fatalf("stale user revision overwritten: %+v %v", repo, err)
			}
		} else if err != nil || repo.writes != 2 {
			t.Fatalf("publication conflict not replanned: %+v %v", repo, err)
		}
	}
}
