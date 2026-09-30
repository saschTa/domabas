package handlers

import (
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func emailOptionalStringMapper(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func emailOptionalIDMapper(value string) *uuid.UUID {
	if value == "" {
		return nil
	}
	id, err := uuid.Parse(value)
	if err != nil {
		return nil
	}
	return &id
}

func emailPublicStatusMapper(value string) string {
	if value == "superseded" {
		return "cancelled"
	}
	return value
}

func emailProviderResponseMapper(p m.EmailProvider) contract.EmailProvider {
	var last *contract.EmailProviderLastRunStatus
	if p.LastRunStatus != "" {
		v := contract.EmailProviderLastRunStatus(emailPublicStatusMapper(p.LastRunStatus))
		last = &v
	}
	return contract.EmailProvider{Id: uuid.MustParse(p.ID), NamespaceId: uuid.MustParse(p.AccountID), Label: p.Label, Host: p.Host, Port: int64(p.Port), Mailbox: p.Mailbox, Enabled: p.Enabled, IntervalMinutes: int64(p.IntervalMinutes), MaxAgeDays: int64(p.MaxAgeDays), PageSize: int64(p.PageSize), Revision: p.Revision, SourceGeneration: p.SourceGeneration, CredentialState: contract.EmailProviderCredentialState(p.CredentialState), ConsentState: contract.EmailProviderConsentState(p.ConsentState), CreatedAt: p.CreatedAt, UpdatedAt: p.UpdatedAt, LastAttemptAt: p.LastAttemptAt, NextDueAt: p.NextPollAt, ActiveRunId: emailOptionalIDMapper(p.ActiveRunID), LastRunStatus: last, FailureCode: emailOptionalStringMapper(p.LastFailureCode), HasPassword: p.HasPassword, Username: emailOptionalStringMapper(p.Username)}
}

func emailProviderSummaryResponseMapper(p m.EmailProvider) contract.EmailProviderSummary {
	v := emailProviderResponseMapper(p)
	var last *contract.EmailProviderSummaryLastRunStatus
	if v.LastRunStatus != nil {
		status := contract.EmailProviderSummaryLastRunStatus(*v.LastRunStatus)
		last = &status
	}
	return contract.EmailProviderSummary{Id: v.Id, NamespaceId: v.NamespaceId, Label: v.Label, Host: v.Host, Port: v.Port, Mailbox: v.Mailbox, Enabled: v.Enabled, IntervalMinutes: v.IntervalMinutes, MaxAgeDays: v.MaxAgeDays, PageSize: v.PageSize, Revision: v.Revision, SourceGeneration: v.SourceGeneration, CredentialState: contract.EmailProviderSummaryCredentialState(v.CredentialState), ConsentState: contract.EmailProviderSummaryConsentState(v.ConsentState), CreatedAt: v.CreatedAt, UpdatedAt: v.UpdatedAt, LastAttemptAt: v.LastAttemptAt, NextDueAt: v.NextDueAt, ActiveRunId: v.ActiveRunId, LastRunStatus: last, FailureCode: v.FailureCode}
}

func emailRunResponseMapper(r m.EmailRun) contract.EmailRun {
	return contract.EmailRun{Id: uuid.MustParse(r.ID), ProviderId: uuid.MustParse(r.ProviderID), NamespaceId: uuid.MustParse(r.AccountID), Reason: contract.EmailRunReason(r.Trigger), Status: contract.EmailRunStatus(emailPublicStatusMapper(r.Status)), Stage: contract.EmailRunStage(r.Stage), CreatedAt: r.CreatedAt, StartedAt: r.StartedAt, FinishedAt: r.FinishedAt, FailureCode: emailOptionalStringMapper(r.FailureCode), MessagesDiscovered: r.MessagesDiscovered, MessagesAccepted: r.MessagesAccepted, MessagesReused: r.MessagesReused, MessagesSkipped: r.MessagesSkipped, MessagesFailed: r.MessagesFailed, MessagesWithContentFailures: r.MessagesWithContentFailures, AttachmentsAccepted: r.AttachmentsAccepted, AttachmentsReused: r.AttachmentsReused, AttachmentsSkipped: r.AttachmentsSkipped, AttachmentsFailed: r.AttachmentsFailed, HasMore: r.HasMore}
}

func emailJobCountsResponseMapper(counts []m.EmailJobStatusCount) *contract.JobStatusCounts {
	out := make([]contract.JobStatusCount, 0, len(counts))
	for _, count := range counts {
		out = append(out, contract.JobStatusCount{Status: count.Status, Count: count.Count})
	}
	return &contract.JobStatusCounts{Groups: out}
}
