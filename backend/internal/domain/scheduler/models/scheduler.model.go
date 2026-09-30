package models

import "errors"

var (
	ErrUnauthorized = errors.New("scheduler unauthorized")
	ErrForbidden    = errors.New("scheduler forbidden")
	ErrConflict     = errors.New("scheduler settings conflict")
)

type SchedulerValidationError struct{ Message string }

func (e SchedulerValidationError) Error() string { return e.Message }

type SchedulerActor struct {
	AccountID, UserID, SessionDigest string
	CredentialRevision               int64
}

type SchedulerResource struct {
	ID, Label                       string
	Limit, MaximumLimit, ActiveJobs int
}

type SchedulerPipeline struct {
	ID, Label   string
	ResourceIDs []string
}

type SchedulerSettings struct {
	Revision        int64
	OllamaQueueSize int
	Resources       []SchedulerResource
	Pipelines       []SchedulerPipeline
}

type SchedulerResourceUpdate struct {
	ID    string
	Limit int
}

type SchedulerSettingsUpdate struct {
	ExpectedRevision int64
	Resources        []SchedulerResourceUpdate
}

func (u SchedulerSettingsUpdate) Validate() error {
	if u.ExpectedRevision < 1 || len(u.Resources) < 1 || len(u.Resources) > 256 {
		return SchedulerValidationError{"invalid workload settings"}
	}
	seen := make(map[string]bool, len(u.Resources))
	for _, resource := range u.Resources {
		if resource.ID == "" || len(resource.ID) > 80 || seen[resource.ID] || resource.Limit < 1 || resource.Limit > 256 {
			return SchedulerValidationError{"invalid workload resource limit"}
		}
		seen[resource.ID] = true
	}
	return nil
}
