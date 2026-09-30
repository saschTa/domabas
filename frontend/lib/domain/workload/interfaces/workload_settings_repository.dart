import '../models/workload_settings.dart';

abstract interface class WorkloadSettingsRepository {
  Future<WorkloadSettings> settings({Future<void>? cancel});
  Future<WorkloadSettings> updateSettings({
    required Map<String, int> limits,
    required int expectedRevision,
    Future<void>? cancel,
  });
  void cancelRequests();
}
