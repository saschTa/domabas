package repos

import (
	"context"
	"errors"

	r "github.com/domabas/domabas/backend/internal/data/realtime/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
)

type RealtimeAuthoritySource interface {
	Snapshot(context.Context, r.RealtimeSubject, []string, []string) (r.RealtimeSnapshot, error)
}
type RealtimeAuthorityRepository struct{ source RealtimeAuthoritySource }

func NewRealtimeAuthorityRepository(source RealtimeAuthoritySource) *RealtimeAuthorityRepository {
	return &RealtimeAuthorityRepository{source: source}
}
func (s *RealtimeAuthorityRepository) Snapshot(ctx context.Context, subject m.RealtimeSubject, signals []m.RealtimeSignal) (m.RealtimeSnapshot, error) {
	accounts := []string{subject.AccountID}
	users := []string{}
	for _, signal := range signals {
		if signal.AccountID != "" {
			accounts = append(accounts, signal.AccountID)
		}
		if signal.Kind == "member_user" && signal.UserID != "" {
			users = append(users, signal.UserID)
		}
	}
	v, err := s.source.Snapshot(ctx, r.RealtimeSubject{UserID: subject.UserID, AccountID: subject.AccountID, SessionDigest: subject.SessionDigest, CredentialRevision: subject.CredentialRevision}, accounts, users)
	if errors.Is(err, r.ErrUnauthorized) {
		return m.RealtimeSnapshot{}, m.ErrUnauthorized
	}
	if err != nil {
		return m.RealtimeSnapshot{}, m.ErrUnavailable
	}
	f := v.Identity
	identity := i.IdentityAuthorityFacts{Principal: i.IdentityPrincipal{UserID: f.Principal.UserID, AccountID: f.Principal.AccountID, SessionDigest: f.Principal.SessionDigest, CredentialRevision: f.Principal.CredentialRevision, MustChangePassword: f.Principal.MustChangePassword, SessionExpiresAt: f.Principal.SessionExpiresAt}, MembershipEnabled: f.MembershipEnabled, SessionAccountID: f.SessionAccountID, SessionUserID: f.SessionUserID, SessionCredentialRevision: f.SessionCredentialRevision, ObservedAt: f.ObservedAt}
	out := m.RealtimeSnapshot{Identity: identity, SystemRole: v.SystemRole, MemberUsers: v.MemberUsers, Memberships: make([]m.RealtimeMembership, 0, len(v.Memberships))}
	for _, a := range v.Memberships {
		out.Memberships = append(out.Memberships, m.RealtimeMembership{AccountID: a.AccountID, Role: a.Role, Owner: a.Owner, Claims: a.Claims, Enabled: a.Enabled})
	}
	return out, nil
}
