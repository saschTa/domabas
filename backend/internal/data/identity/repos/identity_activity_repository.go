package repos

import (
	"context"
	"errors"

	r "github.com/domabas/domabas/backend/internal/data/identity/models"
	m "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
)

type IdentityActivitySource interface {
	IdentityActivityMemberships(context.Context, uuid.UUID) ([]r.IdentityActivityMembershipRecord, error)
	PersonalActivityRecords(context.Context, r.IdentityRecord, r.IdentityActivityPageRequest) (r.IdentityActivityRecords, error)
}

func (s *IdentityActivityRepository) ActivityMemberships(ctx context.Context, userID string) ([]m.IdentityActivityMembership, error) {
	user, err := uuid.Parse(userID)
	if err != nil {
		return nil, m.ErrUnauthorized
	}
	records, err := s.source.IdentityActivityMemberships(ctx, user)
	if err != nil {
		return nil, identityError(err)
	}
	result := make([]m.IdentityActivityMembership, 0, len(records))
	for _, record := range records {
		result = append(result, m.IdentityActivityMembership{AccountID: record.AccountID.String(), Role: m.IdentityRole(record.Role), Owner: record.Owner, Enabled: record.Enabled, Claims: identityPermissionsMapper(record.Claims)})
	}
	return result, nil
}

type IdentityActivityRepository struct {
	source IdentityActivitySource
}

func NewIdentityActivityRepository(source IdentityActivitySource) *IdentityActivityRepository {
	return &IdentityActivityRepository{source: source}
}

func (s *IdentityActivityRepository) PersonalActivity(ctx context.Context, principal m.IdentityPrincipal, page m.IdentityActivityPageRequest) (m.PersonalActivity, error) {
	actor, err := identityPrincipalDomainToRecordMapper(principal)
	if err != nil {
		return m.PersonalActivity{}, err
	}
	query := r.IdentityActivityPageRequest{ActiveCursor: page.ActiveCursor, FinishedCursor: page.FinishedCursor}
	for _, pair := range []struct {
		values []string
		target *[]uuid.UUID
	}{{page.Scope.Documents, &query.Documents}, {page.Scope.Email, &query.Email}, {page.Scope.Batches, &query.Batches}, {page.Scope.Titles, &query.Titles}} {
		*pair.target = []uuid.UUID{}
		for _, value := range pair.values {
			id, err := uuid.Parse(value)
			if err != nil {
				return m.PersonalActivity{}, m.ErrUnauthorized
			}
			*pair.target = append(*pair.target, id)
		}
	}
	records, err := s.source.PersonalActivityRecords(ctx, actor, query)
	if errors.Is(err, r.ErrActivityCursor) {
		return m.PersonalActivity{}, m.IdentityValidationError("invalid activity cursor")
	}
	if errors.Is(err, r.ErrActivityUnavailable) {
		return m.PersonalActivity{}, m.ErrActivityUnavailable
	}
	if err != nil {
		return m.PersonalActivity{}, identityError(err)
	}
	return m.PersonalActivity{Active: identityActivityItemsMapper(records.Active), Finished: identityActivityItemsMapper(records.Finished), ActiveTruncated: records.ActiveTruncated, ActiveNextCursor: records.ActiveNextCursor, FinishedNextCursor: records.FinishedNextCursor, GeneratedAt: records.GeneratedAt.UTC()}, nil
}
