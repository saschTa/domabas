import 'package:domabas_api/api.dart' as api;

import '../../../domain/workload/models/workload_settings.dart';

WorkloadSettings workloadSettingsMapper(api.WorkloadSettings value) {
  final resourceIds = value.resources.map((resource) => resource.id).toSet();
  if (value.revision < 1 ||
      value.ollamaQueueSize < 2 ||
      value.resources.isEmpty ||
      resourceIds.length != value.resources.length ||
      value.pipelines.map((pipeline) => pipeline.id).toSet().length !=
          value.pipelines.length ||
      value.resources.any(
        (resource) =>
            resource.id.trim().isEmpty ||
            resource.label.trim().isEmpty ||
            resource.limit < 1 ||
            resource.maximumLimit < 1 ||
            resource.maximumLimit > 256 ||
            resource.limit > resource.maximumLimit ||
            resource.activeJobs < 0 ||
            (resource.id == 'ollama' &&
                resource.maximumLimit > value.ollamaQueueSize ~/ 2),
      ) ||
      value.pipelines.any(
        (pipeline) =>
            pipeline.id.trim().isEmpty ||
            pipeline.label.trim().isEmpty ||
            pipeline.resourceIds.any((id) => !resourceIds.contains(id)),
      )) {
    throw const FormatException('Invalid workload settings');
  }
  return WorkloadSettings(
    revision: value.revision,
    ollamaQueueSize: value.ollamaQueueSize,
    resources: value.resources.map(
      (resource) => WorkloadResource(
        id: resource.id,
        label: resource.label,
        limit: resource.limit,
        maximumLimit: resource.maximumLimit,
        activeJobs: resource.activeJobs,
      ),
    ),
    pipelines: value.pipelines.map(
      (pipeline) => WorkloadPipeline(
        id: pipeline.id,
        label: pipeline.label,
        resourceIds: pipeline.resourceIds,
      ),
    ),
  );
}
