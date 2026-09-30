import 'dart:async';

import 'package:domabas_api/api.dart' as api;

final class PersonalActivityRemoteDataSource {
  PersonalActivityRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 15),
  });
  final api.IdentityApi _api;
  final Duration timeout;
  final _requests = <Completer<void>>{};
  bool _cancelled = false;
  void cancelRequests() {
    _cancelled = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<api.PersonalActivity> activity({
    String? activeCursor,
    String? finishedCursor,
    Future<void>? cancel,
  }) async {
    if (_cancelled) throw api.ApiException(499, 'Cancelled');
    final abort = Completer<void>();
    _requests.add(abort);
    var timedOut = false;
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    final timer = Timer(timeout, () {
      timedOut = true;
      stop();
    });
    if (cancel != null) unawaited(cancel.then((_) => stop()));
    try {
      final value = await _api
          .getPersonalActivity(
            activeCursor: activeCursor,
            finishedCursor: finishedCursor,
            abortTrigger: abort.future,
          )
          .timeout(timeout);
      if (timedOut) throw TimeoutException('Activity request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      if (value == null) throw const FormatException('Missing activity');
      return value;
    } on TypeError {
      throw const FormatException('Invalid activity');
    } on AssertionError {
      throw const FormatException('Missing activity fields');
    } catch (_) {
      if (timedOut) throw TimeoutException('Activity request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      rethrow;
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}
