import 'dart:async';

import 'package:domabas_api/api.dart' as api;

final class EmailRemoteDataSource {
  EmailRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 20),
  });
  final api.EmailApi _api;
  final Duration timeout;
  final _requests = <Completer<void>>{};
  bool _cancelled = false;
  void cancelRequests() {
    _cancelled = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<api.EmailCapabilities> capabilities(Future<void>? cancel) => _request(
    (abort) => _api.getEmailCapabilities(abortTrigger: abort),
    cancel,
  );
  Future<api.EmailProviderPage> providers(
    int limit,
    String? cursor,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.listEmailProviders(
      limit: limit,
      cursor: cursor,
      abortTrigger: abort,
    ),
    cancel,
  );
  Future<api.EmailProvider> provider(String id, Future<void>? cancel) =>
      _request(
        (abort) => _api.getEmailProvider(id, abortTrigger: abort),
        cancel,
      );
  Future<api.EmailProvider> create(
    api.CreateEmailProvider body,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.createEmailProvider(body, abortTrigger: abort),
    cancel,
  );
  Future<api.EmailProvider> update(
    String id,
    api.UpdateEmailProvider body,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.updateEmailProvider(id, body, abortTrigger: abort),
    cancel,
  );
  Future<void> delete(String id, int revision, Future<void>? cancel) async {
    await _request((abort) async {
      await _api.deleteEmailProvider(id, revision, abortTrigger: abort);
      return true;
    }, cancel);
  }

  Future<api.EmailConnectionTest> test(
    api.TestEmailConnection body,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.testEmailConnection(body, abortTrigger: abort),
    cancel,
  );
  Future<api.EmailRunPage> runs(
    String? id,
    int limit,
    String? cursor,
    String? status,
    bool activeOnly,
    Future<void>? cancel,
  ) => _request(
    (abort) => id == null
        ? _api.listOwnEmailRuns(
            limit: limit,
            cursor: cursor,
            status: status,
            activeOnly: activeOnly ? true : null,
            abortTrigger: abort,
          )
        : _api.listEmailRuns(
            id,
            limit: limit,
            cursor: cursor,
            status: status,
            activeOnly: activeOnly ? true : null,
            abortTrigger: abort,
          ),
    cancel,
  );
  Future<api.EmailRun> run(String id, Future<void>? cancel) =>
      _request((abort) => _api.getEmailRun(id, abortTrigger: abort), cancel);
  Future<api.EmailRun> start(
    String id,
    api.StartEmailRun body,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.startEmailRun(id, body, abortTrigger: abort),
    cancel,
  );
  Future<T> _request<T>(
    Future<T?> Function(Future<void>) send,
    Future<void>? cancel,
  ) async {
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
      final result = await send(abort.future).timeout(timeout);
      if (timedOut) throw TimeoutException('Email request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      if (result == null) throw const FormatException('Missing email response');
      return result;
    } on TypeError {
      throw const FormatException('Invalid email response');
    } on AssertionError {
      throw const FormatException('Missing email fields');
    } catch (_) {
      if (timedOut) throw TimeoutException('Email request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      rethrow;
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}
