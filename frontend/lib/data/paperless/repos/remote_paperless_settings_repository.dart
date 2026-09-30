import 'dart:async';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/paperless/interfaces/paperless_settings_repository.dart';
import '../../../domain/paperless/models/paperless_settings.dart';
import '../datasources/paperless_remote_data_source.dart';
import 'paperless_settings_mapper.dart';

final class RemotePaperlessSettingsRepository
    implements PaperlessSettingsRepository {
  RemotePaperlessSettingsRepository(this._source);

  final PaperlessRemoteDataSource _source;

  @override
  void cancelRequests() => _source.cancelRequests();

  @override
  Future<PaperlessSettings> settings({Future<void>? cancel}) => _translate(
    () async => paperlessSettingsMapper(await _source.settings(cancel)),
  );

  @override
  Future<PaperlessSettings> updateSettings({
    required int retrievalConcurrency,
    required int expectedRevision,
    Future<void>? cancel,
  }) => _translate(
    () async => paperlessSettingsMapper(
      await _source.updateSettings(
        api.UpdatePaperlessSettingsRequest(
          retrievalConcurrency: retrievalConcurrency,
          expectedRevision: expectedRevision,
        ),
        cancel,
      ),
    ),
  );

  Future<T> _translate<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on api.ApiException catch (error) {
      throw PaperlessSettingsFailure(switch (error.code) {
        400 || 422 => 'invalid_request',
        401 => 'unauthorized',
        403 => 'forbidden',
        409 => 'conflict',
        499 => 'cancelled',
        _ => 'unavailable',
      });
    } on FormatException {
      throw const PaperlessSettingsFailure('unavailable');
    } on TimeoutException {
      throw const PaperlessSettingsFailure('unavailable');
    } on http.ClientException {
      throw const PaperlessSettingsFailure('unavailable');
    }
  }
}
