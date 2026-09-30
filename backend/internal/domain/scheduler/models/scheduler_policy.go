package models

import "slices"

const (
	SchedulerMaximumResources     = 256
	SchedulerMaximumLimit         = 256
	SchedulerExternalDefaultLimit = 2
)

func SchedulerResourceMaximum(id string, queueSize int) int {
	if id == "ollama" {
		return min(SchedulerMaximumLimit, queueSize/2)
	}
	return SchedulerMaximumLimit
}

func SchedulerCanAdmit(state string, blocked, fits, olderFeasible bool) bool {
	return state == "active" || state == "waiting" && !blocked && fits && !olderFeasible
}

func PlanSchedulerSettings(current SchedulerSettings, update SchedulerSettingsUpdate) (SchedulerSettingsPlan, error) {
	if err := update.Validate(); err != nil {
		return SchedulerSettingsPlan{}, err
	}
	if current.Revision != update.ExpectedRevision {
		return SchedulerSettingsPlan{}, ErrConflict
	}
	if len(current.Resources) > SchedulerMaximumResources {
		return SchedulerSettingsPlan{}, SchedulerValidationError{Message: "workload provider resource limit reached"}
	}
	plan := SchedulerSettingsPlan{ExpectedRevision: current.Revision, ExpectedQueueSize: current.OllamaQueueSize, ExpectedResources: append([]SchedulerResource(nil), current.Resources...)}
	for _, resource := range current.Resources {
		if resource.ID != "worker" && resource.ID != "ollama" {
			plan.Materialize = append(plan.Materialize, resource)
		}
	}
	for _, resource := range update.Resources {
		index := slices.IndexFunc(current.Resources, func(v SchedulerResource) bool { return v.ID == resource.ID })
		if index < 0 || resource.Limit > current.Resources[index].MaximumLimit {
			return SchedulerSettingsPlan{}, SchedulerValidationError{Message: "workload resource limit exceeds its allowed capacity"}
		}
		if resource.Limit != current.Resources[index].Limit {
			plan.Changes = append(plan.Changes, resource)
		}
	}
	return plan, nil
}
