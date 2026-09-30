final class WorkloadSettings {
  WorkloadSettings({
    required this.revision,
    required this.ollamaQueueSize,
    required Iterable<WorkloadResource> resources,
    required Iterable<WorkloadPipeline> pipelines,
  }) : resources = List.unmodifiable(resources),
       pipelines = List.unmodifiable(pipelines);

  final int revision, ollamaQueueSize;
  final List<WorkloadResource> resources;
  final List<WorkloadPipeline> pipelines;
}

final class WorkloadResource {
  const WorkloadResource({
    required this.id,
    required this.label,
    required this.limit,
    required this.maximumLimit,
    required this.activeJobs,
  });

  final String id, label;
  final int limit, maximumLimit, activeJobs;

  String? validateLimit(String draft) {
    final value = int.tryParse(draft.trim());
    if (!RegExp(r'^[0-9]+$').hasMatch(draft.trim()) ||
        value == null ||
        value < 1 ||
        value > maximumLimit) {
      return 'Enter a whole number from 1 to $maximumLimit.';
    }
    return null;
  }
}

final class WorkloadPipeline {
  WorkloadPipeline({
    required this.id,
    required this.label,
    required Iterable<String> resourceIds,
  }) : resourceIds = List.unmodifiable(resourceIds);

  final String id, label;
  final List<String> resourceIds;
}

final class WorkloadSettingsFailure implements Exception {
  const WorkloadSettingsFailure(this.code);

  final String code;

  String get message => switch (code) {
    'unauthorized' => 'Sign in again to manage workload limits.',
    'forbidden' =>
      'System administrator access is required to manage workload limits.',
    'conflict' => 'Another administrator changed these limits. Refresh to review the saved values before saving your draft.',
    'invalid_request' =>
      'Review the resource limits. Each must be within the allowed range.',
    'cancelled' => 'Request cancelled.',
    _ => 'Workload limits could not be confirmed. Refresh before trying again.',
  };
}
