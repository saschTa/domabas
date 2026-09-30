import 'dart:async';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/workload/interfaces/workload_settings_repository.dart';
import '../../../domain/workload/models/workload_settings.dart';
import '../datasources/workload_remote_data_source.dart';
import 'workload_settings_mapper.dart';

final class RemoteWorkloadSettingsRepository
    implements WorkloadSettingsRepository {
  RemoteWorkloadSettingsRepository(this._source);

  final WorkloadRemoteDataSource _source;

  @override
  void cancelRequests() => _source.cancelRequests();

  @override
  Future<WorkloadSettings> settings({Future<void>? cancel}) => _translate(
    () async => workloadSettingsMapper(await _source.settings(cancel)),
  );

  @override
  Future<WorkloadSettings> updateSettings({
    required Map<String, int> limits,
    required int expectedRevision,
    Future<void>? cancel,
  }) => _translate(
    () async => workloadSettingsMapper(
      await _source.updateSettings(
        api.UpdateWorkloadSettingsRequest(
          expectedRevision: expectedRevision,
          resources: limits.entries
              .map(
                (entry) => api.WorkloadResourceLimit(
                  id: entry.key,
                  limit: entry.value,
                ),
              )
              .toList(),
        ),
        cancel,
      ),
    ),
  );

  Future<T> _translate<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on api.ApiException catch (error) {
      throw WorkloadSettingsFailure(switch (error.code) {
        400 || 422 => 'invalid_request',
        401 => 'unauthorized',
        403 => 'forbidden',
        409 => 'conflict',
        499 => 'cancelled',
        _ => 'unavailable',
      });
    } on FormatException {
      throw const WorkloadSettingsFailure('unavailable');
    } on TimeoutException {
      throw const WorkloadSettingsFailure('unavailable');
    } on http.ClientException {
      throw const WorkloadSettingsFailure('unavailable');
    }
  }
}
