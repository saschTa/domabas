import 'dart:async';

import 'package:domabas_api/api.dart' as api;

final class PaperlessRemoteDataSource {
  PaperlessRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 15),
  });
  final api.PaperlessApi _api;
  final Duration timeout;
  final _requests = <Completer<void>>{};
  bool _cancelled = false;

  void cancelRequests() {
    _cancelled = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<api.PaperlessOptions> options(Future<void>? cancel) => _request(
    (abort) => _api.getPaperlessOptions(abortTrigger: abort),
    cancel,
  );
  Future<api.PaperlessSettings> settings(Future<void>? cancel) => _request(
    (abort) => _api.getPaperlessSettings(abortTrigger: abort),
    cancel,
  );
  Future<api.PaperlessSettings> updateSettings(
    api.UpdatePaperlessSettingsRequest body,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.updatePaperlessSettings(body, abortTrigger: abort),
    cancel,
  );
  Future<api.PaperlessRunPage> runs(
    int limit,
    String? cursor,
    String? status,
    bool activeOnly,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.listPaperlessRuns(
      limit: limit,
      cursor: cursor,
      status: status,
      activeOnly: activeOnly ? true : null,
      abortTrigger: abort,
    ),
    cancel,
  );
  Future<api.PaperlessOutcomePage> outcomes(
    String id,
    int limit,
    String? cursor,
    String? status,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.listPaperlessOutcomes(
      id,
      limit: limit,
      cursor: cursor,
      status: status,
      abortTrigger: abort,
    ),
    cancel,
  );
  Future<api.PaperlessRun> get(String id, Future<void>? cancel) => _request(
    (abort) => _api.getPaperlessRun(id, abortTrigger: abort),
    cancel,
  );
  Future<api.PaperlessRun> start(
    api.StartPaperlessRun body,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.startPaperlessRun(body, abortTrigger: abort),
    cancel,
  );
  Future<api.PaperlessRun> cancelRun(String id, Future<void>? cancel) =>
      _request(
        (abort) => _api.cancelPaperlessRun(id, abortTrigger: abort),
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
      if (timedOut) throw TimeoutException('Paperless request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      if (result == null) {
        throw const FormatException('Missing Paperless response');
      }
      return result;
    } on TypeError {
      throw const FormatException('Invalid Paperless response');
    } on AssertionError {
      throw const FormatException('Missing Paperless response fields');
    } catch (_) {
      if (timedOut) throw TimeoutException('Paperless request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      rethrow;
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}
