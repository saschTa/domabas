package services

import (
	"context"
	"errors"
	"sort"

	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	p "github.com/domabas/domabas/backend/internal/domain/realtime/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
)

type RealtimeService struct {
	repository    p.RealtimeRepository
	authenticator p.RealtimeAuthenticator
	policy        p.RealtimePolicy
}

func NewRealtimeService(repository p.RealtimeRepository, authenticator p.RealtimeAuthenticator, policy p.RealtimePolicy) *RealtimeService {
	return &RealtimeService{repository: repository, authenticator: authenticator, policy: policy}
}
func (s *RealtimeService) Authenticate(ctx context.Context, token string) (m.RealtimeSubject, error) {
	v, err := s.authenticator.Authenticate(ctx, token)
	if errors.Is(err, i.ErrUnauthorized) || (err == nil && v.MustChangePassword) {
		return m.RealtimeSubject{}, m.ErrUnauthorized
	}
	if err != nil {
		return m.RealtimeSubject{}, m.ErrUnavailable
	}
	return m.RealtimeSubject{UserID: v.UserID, AccountID: v.AccountID, SessionDigest: v.SessionDigest, CredentialRevision: v.CredentialRevision}, nil
}
func (s *RealtimeService) Authorize(ctx context.Context, subject m.RealtimeSubject, signals []m.RealtimeSignal, resync bool) ([]m.RealtimeTopic, error) {
	if len(signals) > 64 {
		return nil, m.ErrUnavailable
	}
	v, err := s.repository.Snapshot(ctx, subject, signals)
	if err != nil {
		return nil, err
	}
	if err := v.Identity.ValidateSession(subject.SessionDigest); err != nil || v.Identity.Principal.MustChangePassword ||
		v.Identity.Principal.AccountID != subject.AccountID || v.Identity.Principal.UserID != subject.UserID || v.Identity.Principal.CredentialRevision != subject.CredentialRevision {
		return nil, m.ErrUnauthorized
	}
	accounts := make(map[string]m.RealtimeMembership, len(v.Memberships))
	for _, account := range v.Memberships {
		if account.Enabled {
			accounts[account.AccountID] = account
		}
	}
	allows := func(account, permission string) bool {
		member, ok := accounts[account]
		return ok && s.policy.AllowsAuthority(member.Role, member.Owner, member.Claims, "", permission)
	}
	if !allows(subject.AccountID, "realtime:connect") {
		return nil, m.ErrForbidden
	}
	system := func(permission string) bool {
		return s.policy.AllowsAuthority("", false, nil, v.SystemRole, permission)
	}
	result := map[m.RealtimeTopic]bool{}
	current := func() {
		result[m.Identity], result[m.Activity] = true, true
		result[m.Documents] = allows(subject.AccountID, "documents:read")
		result[m.Processing] = allows(subject.AccountID, "documents:jobs:read") || allows(subject.AccountID, "documents:reindex")
		result[m.Email] = allows(subject.AccountID, "email:manage")
		result[m.Paperless] = allows(subject.AccountID, "paperless:import") && allows(subject.AccountID, "documents:read") && allows(subject.AccountID, "documents:upload")
		result[m.Chat] = allows(subject.AccountID, "chat:use")
		result[m.Members] = allows(subject.AccountID, "users:manage")
		result[m.Configuration] = system("system:document-processing:manage")
		result[m.SystemUsers] = system("system:users:manage")
	}
	if resync {
		current()
	}
	for _, signal := range signals {
		own := signal.UserID == subject.UserID
		connected := allows(signal.AccountID, "realtime:connect")
		activity := connected && allows(signal.AccountID, "activity:read:own")
		same := signal.AccountID == subject.AccountID
		processing := allows(signal.AccountID, "documents:jobs:read") || allows(signal.AccountID, "documents:reindex")
		switch signal.Kind {
		case "authority":
			if own {
				result[m.Identity], result[m.Activity] = true, true
			}
		case "documents":
			if same && allows(signal.AccountID, "documents:read") {
				result[m.Documents] = true
			}
			if same && processing {
				result[m.Processing] = true
			}
			if activity && allows(signal.AccountID, "documents:read") {
				result[m.Activity] = true
			}
		case "document_job", "batch":
			if same && processing {
				result[m.Processing] = true
			}
			if own && activity && (signal.Kind == "document_job" || processing) {
				result[m.Activity] = true
			}
		case "configuration":
			if system("system:document-processing:manage") {
				result[m.Configuration] = true
			}
		case "paperless":
			if own && same && allows(signal.AccountID, "paperless:import") && allows(signal.AccountID, "documents:read") && allows(signal.AccountID, "documents:upload") {
				result[m.Paperless] = true
			}
		case "chat":
			if own && same && allows(signal.AccountID, "chat:use") {
				result[m.Chat] = true
			}
		case "email":
			if own && allows(signal.AccountID, "email:manage") {
				if same {
					result[m.Email] = true
				}
				if activity {
					result[m.Activity] = true
				}
			}
		case "account":
			if _, ok := accounts[signal.AccountID]; ok {
				result[m.Identity] = true
			}
			if activity {
				result[m.Activity] = true
			}
		case "members":
			if same && allows(subject.AccountID, "users:manage") {
				result[m.Members] = true
			}
		case "member_user":
			if v.MemberUsers[signal.UserID] && allows(subject.AccountID, "users:manage") {
				result[m.Members] = true
			}
		case "system_users":
			if system("system:users:manage") {
				result[m.SystemUsers] = true
			}
		}
	}
	topics := make([]m.RealtimeTopic, 0, len(result))
	for topic, allowed := range result {
		if allowed {
			topics = append(topics, topic)
		}
	}
	sort.Slice(topics, func(i, j int) bool { return topics[i] < topics[j] })
	return topics, nil
}
