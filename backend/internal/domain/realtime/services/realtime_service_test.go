package services

import (
	"context"
	"errors"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"slices"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
)

type repositoryStub struct {
	snapshot m.RealtimeSnapshot
	err      error
}

func (r *repositoryStub) Snapshot(context.Context, m.RealtimeSubject, []m.RealtimeSignal) (m.RealtimeSnapshot, error) {
	return r.snapshot, r.err
}

type policyStub struct{}

func (policyStub) AllowsAuthority(role string, owner bool, claims []string, systemRole, permission string) bool {
	if permission == "system:users:manage" || permission == "system:document-processing:manage" {
		return systemRole == "admin"
	}
	return owner || slices.Contains(claims, permission)
}
func TestTopicAuthorityAndCrossLibraryRemoval(t *testing.T) {
	subject := m.RealtimeSubject{UserID: "owner", AccountID: "a", SessionDigest: "digest", CredentialRevision: 1}
	repo := &repositoryStub{snapshot: m.RealtimeSnapshot{Memberships: []m.RealtimeMembership{{AccountID: "a", Enabled: true, Claims: []string{"realtime:connect", "documents:jobs:read"}}, {AccountID: "b", Enabled: true, Claims: []string{"realtime:connect", "activity:read:own", "documents:read", "email:manage"}}}}}
	repo.snapshot.Identity = i.IdentityAuthorityFacts{Principal: i.IdentityPrincipal{UserID: subject.UserID, AccountID: subject.AccountID, SessionDigest: subject.SessionDigest, CredentialRevision: 1}, MembershipEnabled: true, SessionAccountID: subject.AccountID, SessionUserID: subject.UserID, SessionCredentialRevision: 1, ObservedAt: time.Now()}
	service := NewRealtimeService(repo, nil, policyStub{})
	cases := []struct {
		name   string
		signal m.RealtimeSignal
		want   []m.RealtimeTopic
	}{
		{"terminal title and deletion", m.RealtimeSignal{Kind: "documents", AccountID: "a"}, []m.RealtimeTopic{m.Processing}},
		{"own cross-library title", m.RealtimeSignal{Kind: "documents", AccountID: "b"}, []m.RealtimeTopic{m.Activity}},
		{"private other email", m.RealtimeSignal{Kind: "email", AccountID: "b", UserID: "other"}, nil},
		{"own cross-library email", m.RealtimeSignal{Kind: "email", AccountID: "b", UserID: "owner"}, []m.RealtimeTopic{m.Activity}},
		{"other job still namespace processing", m.RealtimeSignal{Kind: "document_job", AccountID: "a", UserID: "other"}, []m.RealtimeTopic{m.Processing}},
		{"removed library refresh", m.RealtimeSignal{Kind: "authority", AccountID: "removed", UserID: "owner"}, []m.RealtimeTopic{m.Activity, m.Identity}},
		{"other authority private", m.RealtimeSignal{Kind: "authority", AccountID: "a", UserID: "other"}, nil},
		{"system authority separate", m.RealtimeSignal{Kind: "configuration"}, nil},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			got, err := service.Authorize(context.Background(), subject, []m.RealtimeSignal{test.signal}, false)
			if err != nil || !slices.Equal(got, test.want) {
				t.Fatalf("topics=%v err=%v want=%v", got, err, test.want)
			}
		})
	}
	got, err := service.Authorize(context.Background(), subject, nil, true)
	if err != nil || !slices.Equal(got, []m.RealtimeTopic{m.Activity, m.Identity, m.Processing}) {
		t.Fatalf("resync=%v %v", got, err)
	}
	repo.snapshot.Memberships = nil
	if _, err = service.Authorize(context.Background(), subject, nil, true); !errors.Is(err, m.ErrForbidden) {
		t.Fatal(err)
	}
	repo.err = m.ErrUnauthorized
	if _, err = service.Authorize(context.Background(), subject, nil, true); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatal(err)
	}
}

func TestPrivateJobTopicsRequireOwnerNamespaceAndFeatureClaims(t *testing.T) {
	subject := m.RealtimeSubject{UserID: "owner", AccountID: "a", SessionDigest: "digest", CredentialRevision: 1}
	repo := &repositoryStub{snapshot: m.RealtimeSnapshot{
		Identity:    i.IdentityAuthorityFacts{Principal: i.IdentityPrincipal{UserID: subject.UserID, AccountID: subject.AccountID, SessionDigest: subject.SessionDigest, CredentialRevision: 1}, MembershipEnabled: true, SessionAccountID: subject.AccountID, SessionUserID: subject.UserID, SessionCredentialRevision: 1, ObservedAt: time.Now()},
		Memberships: []m.RealtimeMembership{{AccountID: "a", Enabled: true, Claims: []string{"realtime:connect", "paperless:import", "documents:read", "documents:upload", "chat:use"}}},
	}}
	service := NewRealtimeService(repo, nil, policyStub{})
	for _, kind := range []string{"paperless", "chat"} {
		for _, test := range []struct {
			account, user string
			allowed       bool
		}{{"a", "owner", true}, {"a", "other", false}, {"b", "owner", false}} {
			topics, err := service.Authorize(t.Context(), subject, []m.RealtimeSignal{{Kind: kind, AccountID: test.account, UserID: test.user}}, false)
			if err != nil || slices.Contains(topics, m.RealtimeTopic(kind)) != test.allowed {
				t.Fatalf("%s %+v: %v %v", kind, test, topics, err)
			}
		}
	}
	topics, err := service.Authorize(t.Context(), subject, nil, true)
	if err != nil || !slices.Contains(topics, m.Paperless) || !slices.Contains(topics, m.Chat) {
		t.Fatalf("ready: %v %v", topics, err)
	}
	repo.snapshot.Memberships[0].Claims = []string{"realtime:connect", "paperless:import", "documents:read"}
	topics, err = service.Authorize(t.Context(), subject, []m.RealtimeSignal{{Kind: "paperless", AccountID: "a", UserID: "owner"}, {Kind: "chat", AccountID: "a", UserID: "owner"}}, true)
	if err != nil || slices.Contains(topics, m.Paperless) || slices.Contains(topics, m.Chat) {
		t.Fatalf("revoked: %v %v", topics, err)
	}
}
