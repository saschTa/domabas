import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/document/models/document_limits.dart';
import '../models/document_thumbnail_mapper.dart';

final class DocumentRemoteDataSource {
  DocumentRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 15),
    this.searchTimeout = const Duration(seconds: 35),
  });
  final api.DocumentsApi _api;
  final Duration timeout;
  final Duration searchTimeout;
  final _requests = <Completer<void>>{};
  bool _cancelled = false;

  void cancelRequests() {
    _cancelled = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<api.DocumentList> list({
    required int limit,
    required int offset,
    String? cursor,
    Future<void>? cancel,
  }) => _request((abort) async {
    final json = _json(
      await _api.listDocumentsWithHttpInfo(
        limit: limit,
        offset: offset,
        cursor: cursor,
        abortTrigger: abort,
      ),
    );
    if (json['items'] is! List) {
      throw const FormatException('Invalid document page');
    }
    for (final item in json['items'] as List) {
      validateDocumentThumbnailJson(item as Map<String, dynamic>);
    }
    return api.DocumentList.fromJson(json);
  }, cancel: cancel);
  Future<api.DocumentSearchResults> search(
    Map<String, Object> fields, {
    Future<void>? cancel,
  }) => _request(
    (abort) async {
      final response = await _api.searchDocumentsWithHttpInfo(
        _DocumentSearch(fields),
        abortTrigger: abort,
      );
      if (response.statusCode != 200) {
        throw api.ApiException(response.statusCode, 'Search failed');
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic> || json['items'] is! List) {
        throw const FormatException('Invalid search response');
      }
      for (final item in json['items'] as List) {
        final document =
            (item as Map<String, dynamic>)['document'] as Map<String, dynamic>;
        validateDocumentThumbnailJson(document);
        if (!document.containsKey('original')) continue;
        final original = document['original'];
        if (original is! Map<String, dynamic> ||
            original['sha256'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(original['sha256'] as String) ||
            !const {
              'application/pdf',
              'image/png',
              'image/jpeg',
              'message/rfc822',
            }.contains(original['mediaType']) ||
            original['size'] is! int ||
            (original['size'] as int) < 1 ||
            (original['size'] as int) > documentOriginalByteLimit) {
          throw const FormatException('Invalid search original');
        }
      }
      return api.DocumentSearchResults.fromJson(json);
    },
    cancel: cancel,
    deadline: searchTimeout,
  );
  Future<api.Document> create({
    required String title,
    required String description,
  }) => _request(
    (abort) async => _document(
      await _api.createDocumentWithHttpInfo(
        api.CreateDocument(title: title, description: description),
        abortTrigger: abort,
      ),
    ),
  );
  Future<api.Document> getById(String id, {Future<void>? cancel}) => _request(
    (abort) async =>
        _document(await _api.getDocumentWithHttpInfo(id, abortTrigger: abort)),
    cancel: cancel,
  );
  Future<api.Document> update(
    String id,
    Map<String, Object> changes, {
    Future<void>? cancel,
  }) => _request(
    (abort) async => _document(
      await _api.updateDocumentWithHttpInfo(
        id,
        _DocumentPatch(changes),
        abortTrigger: abort,
      ),
    ),
    cancel: cancel,
  );
  Future<api.DocumentEmailLinks> emailLinks(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) => _request(
    (abort) => _api.getDocumentEmailLinks(
      id,
      limit: 20,
      cursor: cursor,
      abortTrigger: abort,
    ),
    cancel: cancel,
  );
  Future<api.DocumentEmailParents> emailParents(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) => _request(
    (abort) => _api.getDocumentEmailParents(
      id,
      limit: 20,
      cursor: cursor,
      abortTrigger: abort,
    ),
    cancel: cancel,
  );
  Future<api.DocumentOCR> getOcr(String id, {Future<void>? cancel}) => _request(
    (abort) => _api.getDocumentOCR(id, abortTrigger: abort),
    cancel: cancel,
  );
  Future<api.DocumentOCR> updateOcr(
    String id,
    int revision,
    String text, {
    Future<void>? cancel,
  }) => _request(
    (abort) => _api.updateDocumentOCR(
      id,
      api.UpdateDocumentOCR(revision: revision, text: text),
      abortTrigger: abort,
    ),
    cancel: cancel,
  );
  Future<void> delete(String id, {Future<void>? cancel}) async {
    await _request((abort) async {
      final response = await _api.deleteDocumentWithHttpInfo(
        id,
        abortTrigger: abort,
      );
      if (response.statusCode != 204) {
        throw api.ApiException(response.statusCode, 'Delete failed');
      }
      return true;
    }, cancel: cancel);
  }

  Future<void> unlock(
    String id,
    int generation,
    String password, {
    Future<void>? cancel,
  }) async {
    await _request(
      (abort) async {
        final response = await _api.unlockDocumentWithHttpInfo(
          id,
          api.UnlockDocument(password: password, generation: generation),
          abortTrigger: abort,
        );
        if (response.statusCode != 202) {
          var code = 'Unlock failed';
          if (response.statusCode == 400) {
            final body = jsonDecode(utf8.decode(response.bodyBytes));
            if (body is Map<String, dynamic> &&
                body['code'] == 'invalid_pdf_password') {
              code = 'invalid_pdf_password';
            }
          }
          throw api.ApiException(response.statusCode, code);
        }
        return true;
      },
      cancel: cancel,
      deadline: const Duration(seconds: 120),
    );
  }

  Future<void> retry(String id, {Future<void>? cancel}) async {
    await _request(
      (abort) => _api.retryDocument(id, abortTrigger: abort),
      cancel: cancel,
    );
  }

  Future<api.DocumentAIProcessing> retryAI(
    String id,
    String requestId,
    int configurationRevision, {
    Future<void>? cancel,
  }) => _request(
    (abort) => _api.retryDocumentAI(
      id,
      api.CreateDocumentReindexBatch(
        requestId: requestId,
        configurationRevision: configurationRevision,
      ),
      abortTrigger: abort,
    ),
    cancel: cancel,
  );

  Future<Uint8List> download(String id, {Future<void>? cancel}) => _request(
    (abort) async {
      final response = await _api.downloadDocumentWithHttpInfo(
        id,
        abortTrigger: abort,
      );
      if (response.statusCode != 200) {
        throw api.ApiException(response.statusCode, 'Download failed');
      }
      if (response.bodyBytes.length > documentOriginalByteLimit) {
        throw api.ApiException(413, 'File too large');
      }
      return response.bodyBytes;
    },
    cancel: cancel,
    deadline: const Duration(seconds: 120),
  );

  Future<Uint8List> thumbnail(
    String id,
    String sha256, {
    Future<void>? cancel,
  }) => _request((abort) async {
    final response = await _api.getDocumentThumbnailWithHttpInfo(
      id,
      sha256,
      abortTrigger: abort,
    );
    if (response.statusCode != 200) {
      throw api.ApiException(response.statusCode, 'Thumbnail unavailable');
    }
    if (response.bodyBytes.length > documentThumbnailByteLimit) {
      throw api.ApiException(413, 'Thumbnail too large');
    }
    if (response.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase() !=
        'image/jpeg') {
      throw const FormatException('Invalid thumbnail media type');
    }
    return response.bodyBytes;
  }, cancel: cancel);

  Map<String, dynamic> _json(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw api.ApiException(response.statusCode, 'Document request failed');
    }
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid document response');
    }
    return value;
  }

  api.Document? _document(http.Response response) {
    final value = _json(response);
    validateDocumentThumbnailJson(value);
    return api.Document.fromJson(value);
  }

  Future<T> _request<T>(
    Future<T?> Function(Future<void>) send, {
    Future<void>? cancel,
    Duration? deadline,
  }) async {
    if (_cancelled) throw api.ApiException(499, 'Cancelled');
    final abort = Completer<void>();
    _requests.add(abort);
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    final limit = deadline ?? timeout;
    final timer = Timer(limit, stop);
    if (cancel != null) unawaited(cancel.then((_) => stop()));
    try {
      final response = await send(abort.future).timeout(limit);
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      if (response == null) {
        throw const FormatException('Missing response body');
      }
      return response;
    } on TypeError {
      throw const FormatException('Response does not match the API contract');
    } on AssertionError {
      throw const FormatException('Response is missing required fields');
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}

final class _DocumentPatch extends api.UpdateDocument {
  _DocumentPatch(this.changes);
  final Map<String, Object> changes;
  @override
  Map<String, dynamic> toJson() => changes;
}

final class _DocumentSearch extends api.DocumentSearch {
  _DocumentSearch(this.fields)
    : super(
        query: fields['query']! as String,
        mode: api.DocumentSearchModeEnum.hybrid,
      );
  final Map<String, Object> fields;
  @override
  Map<String, dynamic> toJson() => fields;
}
