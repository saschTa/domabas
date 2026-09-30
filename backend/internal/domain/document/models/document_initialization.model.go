package models

type DocumentInitializationFacts struct {
	Adopted, SnapshotPresent bool
	Revision                 int64
	Language, Segmentation   string
	ManifestRevision         *int64
	ManifestFingerprint      *string
	ContextLength            int
	LMStudioCompatibility    bool
	PropertyThinkingEnabled  bool
	InvoiceThinkingEnabled   bool
	Previous                 DocumentProcessingConfiguration
}
type DocumentInitializationCommand struct {
	Expected                              DocumentInitializationFacts
	Configuration                         DocumentProcessingConfiguration
	Noop, RescheduleAI, CheckDrift, Drift bool
	BatchReason                           string
}

func PlanDocumentInitialization(facts DocumentInitializationFacts) (DocumentInitializationCommand, error) {
	command := DocumentInitializationCommand{Expected: facts}
	target := DefaultConfiguration()
	target.Revision, target.Language, target.Segmentation = facts.Revision, facts.Language, facts.Segmentation
	installedFP, err := target.ManifestFingerprint()
	if err != nil {
		return command, err
	}
	if facts.ManifestRevision != nil && (*facts.ManifestRevision > target.ManifestRevision || (*facts.ManifestRevision == target.ManifestRevision && (facts.ManifestFingerprint == nil || *facts.ManifestFingerprint != installedFP))) {
		return command, ErrUnavailable
	}
	if facts.SnapshotPresent {
		target.LLM = facts.Previous.LLM
	}
	mandatory, err := target.CanonicalFingerprint()
	if err != nil {
		return command, err
	}
	mandatoryChanged := facts.SnapshotPresent && facts.Previous.Fingerprint != mandatory
	target.LLM.ContextLength = facts.ContextLength
	target.LLM.LMStudioCompatibility = facts.LMStudioCompatibility
	target.LLM.PropertyThinkingEnabled = facts.PropertyThinkingEnabled
	target.LLM.InvoiceThinkingEnabled = facts.InvoiceThinkingEnabled
	target.Fingerprint, err = target.CanonicalFingerprint()
	if err != nil {
		return command, err
	}
	changed := facts.SnapshotPresent && facts.Previous.Fingerprint != target.Fingerprint
	if changed {
		target.Revision++
	}
	command.Configuration = target
	command.Noop = facts.Adopted && facts.SnapshotPresent && !changed && facts.ManifestRevision != nil && *facts.ManifestRevision == target.ManifestRevision
	if mandatoryChanged {
		command.BatchReason = "configuration_change"
	}
	command.RescheduleAI = changed && !facts.Previous.LLM.Equal(target.LLM)
	command.CheckDrift = !facts.Adopted && !changed
	return command, nil
}
