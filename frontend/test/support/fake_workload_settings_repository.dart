import 'package:domabas/domain/workload/interfaces/workload_settings_repository.dart';
import 'package:domabas/domain/workload/models/workload_settings.dart';

WorkloadSettings testWorkloadSettings({
  int revision = 1,
  int workerLimit = 4,
  int embeddingLimit = 8,
  int embeddingMaximum = 64,
  int activeEmbeddings = 0,
}) => WorkloadSettings(
  revision: revision,
  embeddingQueueSize: 128,
  resources: [
    WorkloadResource(
      id: 'worker',
      label: 'Worker',
      limit: workerLimit,
      maximumLimit: 256,
      activeJobs: 2,
    ),
    WorkloadResource(
      id: 'embedding-runtime',
      label: 'Embedding runtime',
      limit: embeddingLimit,
      maximumLimit: embeddingMaximum,
      activeJobs: activeEmbeddings,
    ),
    const WorkloadResource(
      id: 'external:abc',
      label: 'http://192.0.2.1:1234',
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
      resourceIds: ['worker', 'embedding-runtime'],
    ),
    WorkloadPipeline(
      id: 'chat',
      label: 'AI chat',
      resourceIds: ['worker', 'external:abc'],
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
      embeddingLimit: limits['embedding-runtime']!,
    );
    return current;
  }

  @override
  void cancelRequests() {}
}
