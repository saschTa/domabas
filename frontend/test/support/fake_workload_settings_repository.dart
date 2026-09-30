import 'package:domabas/domain/workload/interfaces/workload_settings_repository.dart';
import 'package:domabas/domain/workload/models/workload_settings.dart';

WorkloadSettings testWorkloadSettings({
  int revision = 1,
  int workerLimit = 4,
  int ollamaLimit = 8,
  int ollamaMaximum = 64,
  int activeOllama = 0,
}) => WorkloadSettings(
  revision: revision,
  ollamaQueueSize: 128,
  resources: [
    WorkloadResource(
      id: 'worker',
      label: 'Worker',
      limit: workerLimit,
      maximumLimit: 256,
      activeJobs: 2,
    ),
    WorkloadResource(
      id: 'ollama',
      label: 'Ollama',
      limit: ollamaLimit,
      maximumLimit: ollamaMaximum,
      activeJobs: activeOllama,
    ),
    const WorkloadResource(
      id: 'provider:abc',
      label: 'External AI · example.test',
      limit: 2,
      maximumLimit: 256,
      activeJobs: 0,
    ),
  ],
  pipelines: [
    WorkloadPipeline(
      id: 'paperless',
      label: 'Paperless retrieval',
      resourceIds: ['worker'],
    ),
    WorkloadPipeline(
      id: 'document',
      label: 'Document ingestion',
      resourceIds: ['worker', 'ollama'],
    ),
    WorkloadPipeline(
      id: 'chat',
      label: 'AI chat',
      resourceIds: ['worker', 'provider:abc'],
    ),
  ],
);

final class FakeWorkloadSettingsRepository
    implements WorkloadSettingsRepository {
  WorkloadSettings current = testWorkloadSettings();
  int reads = 0;
  final writes = <({Map<String, int> limits, int revision})>[];
  Future<WorkloadSettings> Function()? onRead, onWrite;
  Future<void>? lastCancel;

  @override
  Future<WorkloadSettings> settings({Future<void>? cancel}) async {
    reads++;
    lastCancel = cancel;
    return onRead == null ? current : await onRead!();
  }

  @override
  Future<WorkloadSettings> updateSettings({
    required Map<String, int> limits,
    required int expectedRevision,
    Future<void>? cancel,
  }) async {
    writes.add((limits: Map.of(limits), revision: expectedRevision));
    lastCancel = cancel;
    if (onWrite != null) return onWrite!();
    current = testWorkloadSettings(
      revision: expectedRevision + 1,
      workerLimit: limits['worker']!,
      ollamaLimit: limits['ollama']!,
    );
    return current;
  }

  @override
  void cancelRequests() {}
}
