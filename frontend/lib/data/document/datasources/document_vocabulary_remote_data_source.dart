import 'dart:async';
import 'dart:convert';

import 'package:domabas_api/api.dart' as api;

final class DocumentVocabularyRemoteDataSource {
  DocumentVocabularyRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 15),
  });
  final api.DocumentsApi _api;
  final Duration timeout;
  final _requests = <Completer<void>>{};
  bool _closed = false;

  void cancelRequests() {
    _closed = true;
    for (final request in _requests) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<api.DocumentVocabularyPage> lookup(
    String field, {
    required String query,
    required int limit,
    String? cursor,
    Future<void>? cancel,
  }) async {
    if (_closed) throw api.ApiException(499, 'Cancelled');
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
      final response = await _api
          .listDocumentVocabularyWithHttpInfo(
            field,
            query: query,
            limit: limit,
            cursor: cursor,
            abortTrigger: abort.future,
          )
          .timeout(
            timeout,
            onTimeout: () {
              timedOut = true;
              stop();
              throw TimeoutException('Vocabulary request timed out');
            },
          );
      if (timedOut) throw TimeoutException('Vocabulary request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      if (response.statusCode != 200) {
        throw api.ApiException(
          response.statusCode,
          'Vocabulary request failed',
        );
      }
      if (response.bodyBytes.length > 128 * 1024) {
        throw const FormatException('Oversized vocabulary response');
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic> ||
          value.keys.any((key) => key != 'items' && key != 'nextCursor') ||
          value['items'] is! List ||
          (value['items'] as List).length > limit ||
          value.containsKey('nextCursor') && value['nextCursor'] is! String) {
        throw const FormatException('Invalid vocabulary response');
      }
      for (final item in value['items'] as List) {
        if (item is! Map<String, dynamic> ||
            item.length != 2 ||
            item['key'] is! String ||
            item['value'] is! String) {
          throw const FormatException('Invalid vocabulary option');
        }
      }
      return api.DocumentVocabularyPage.fromJson(value)!;
    } on TypeError {
      throw const FormatException('Invalid vocabulary response');
    } on AssertionError {
      throw const FormatException('Missing vocabulary fields');
    } catch (_) {
      if (timedOut) throw TimeoutException('Vocabulary request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      rethrow;
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}
