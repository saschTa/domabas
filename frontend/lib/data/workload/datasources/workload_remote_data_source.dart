import 'dart:async';

import 'package:domabas_api/api.dart' as api;

final class WorkloadRemoteDataSource {
  WorkloadRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 15),
  });

  final api.SystemApi _api;
  final Duration timeout;
  final _requests = <Completer<void>>{};
  bool _cancelled = false;

  void cancelRequests() {
    _cancelled = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<api.WorkloadSettings> settings(Future<void>? cancel) => _request(
    (abort) => _api.getWorkloadSettings(abortTrigger: abort),
    cancel,
  );

  Future<api.WorkloadSettings> updateSettings(
    api.UpdateWorkloadSettingsRequest body,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.updateWorkloadSettings(body, abortTrigger: abort),
    cancel,
  );

  Future<T> _request<T>(
    Future<T?> Function(Future<void>) send,
    Future<void>? cancel,
  ) async {
    if (_cancelled) throw api.ApiException(499, 'Cancelled');
    final abort = Completer<void>();
    _requests.add(abort);
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      stop();
    });
    if (cancel != null) unawaited(cancel.then((_) => stop()));
    try {
      final result = await send(abort.future).timeout(timeout);
      if (timedOut) {
        throw TimeoutException('Workload settings request timed out');
      }
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      if (result == null) {
        throw const FormatException('Missing workload settings');
      }
      return result;
    } on TypeError {
      throw const FormatException('Invalid workload settings');
    } on AssertionError {
      throw const FormatException('Missing workload settings fields');
    } catch (_) {
      if (timedOut) {
        throw TimeoutException('Workload settings request timed out');
      }
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      rethrow;
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}
