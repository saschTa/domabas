import 'dart:async';
import 'dart:convert';

import 'package:domabas/app/limited_response_client.dart';
import 'package:domabas/data/document/datasources/document_remote_data_source.dart';
import 'package:domabas/data/document/datasources/document_vocabulary_remote_data_source.dart';
import 'package:domabas/data/document/repos/remote_document_repository.dart';
import 'package:domabas/data/document/repos/remote_document_vocabulary_repository.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/domain/document/models/document_vocabulary.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Matcher _failure(DocumentFailureKind kind) => throwsA(
  isA<DocumentFailure>().having((failure) => failure.kind, 'kind', kind),
);

void main() {
  final key = 'a' * 64;
  for (final malformed in <Object?>[
    null,
    {},
    {'items': 'bad'},
    {
      'items': [null],
    },
    {
      'items': [7],
    },
    {
      'items': [
        {'key': 'a' * 64},
      ],
    },
    {'items': <Object>[], 'nextCursor': null},
    {
      'items': [
        {'key': 'short', 'value': 'valid'},
      ],
    },
    {
      'items': [
        {'key': 'a' * 64, 'value': ' valid '},
      ],
    },
    {
      'items': [
        {'key': 'a' * 64, 'value': '\ud800'},
      ],
    },
    {
      'items': [
        {'key': 'a' * 64, 'value': '😀' * 321},
      ],
    },
    {
      'items': [
        {'key': 'a' * 64, 'value': 'one'},
        {'key': 'a' * 64, 'value': 'two'},
      ],
    },
    {'items': <Object>[], 'nextCursor': 'bad cursor'},
  ]) {
    test(
      'generated vocabulary transport rejects malformed wire shape ${jsonEncode(malformed)}',
      () async {
        final client = api.ApiClient(basePath: 'http://example.test')
          ..client.close();
        client.client = MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode(malformed)),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        addTearDown(client.client.close);
        final repository = RemoteDocumentVocabularyRepository(
          DocumentVocabularyRemoteDataSource(api.DocumentsApi(client)),
        );
        await expectLater(
          repository.lookup(DocumentVocabularyField.sender),
          _failure(DocumentFailureKind.invalidResponse),
        );
      },
    );
  }

  test('FEFF, Unicode and maximal originals survive lookup, selected criteria and generated request JSON unchanged', () async {
    final client = api.ApiClient(basePath: 'http://example.test')
      ..client.close();
    final values = ['\ufeffİΣ@EXAMPLE\ufeff', '😀' * 320, '<' * 320];
    final searches = <Map<String, dynamic>>[];
    var original = values.first;
    client.client = MockClient((request) async {
      if (request.method == 'GET') {
        expect(request.url.path, '/api/v1/documents/vocabulary');
        expect(request.url.queryParameters['field'], 'sender');
        expect(request.url.queryParameters['limit'], '40');
        final rawQuery = request.url.query
            .split('&')
            .singleWhere((part) => part.startsWith('query='))
            .substring(6);
        final bytes = latin1.encode(
          Uri.decodeQueryComponent(rawQuery, encoding: latin1),
        );
        expect(utf8.decode([0x78, ...bytes]).substring(1), original);
        return http.Response(
          jsonEncode({
            'items': [
              {'key': key, 'value': original},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      searches.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"items":[],"total":0}', 200);
    });
    addTearDown(client.client.close);
    final documents = RemoteDocumentRepository(
      DocumentRemoteDataSource(api.DocumentsApi(client)),
    );
    final vocabulary = RemoteDocumentVocabularyRepository(
      DocumentVocabularyRemoteDataSource(api.DocumentsApi(client)),
    );
    for (final value in values) {
      original = value;
      final option = (await vocabulary.lookup(
        DocumentVocabularyField.sender,
        query: ' $value ',
      )).items.single;
      expect(option.value, value);
      final criteria = DocumentSearchCriteria(
        query: '\ufeffNeedle\ufeff',
        sender: option.value,
        senderMatch: DocumentAddressMatch.exact,
        recipient: '%_literal',
        tags: ['\ufeffTag\ufeff'],
        canonicalTags: true,
      );
      await documents.search(criteria);
      expect(searches.last['sender'], value);
      expect(searches.last['senderMatch'], 'exact');
      expect(searches.last.containsKey('recipientMatch'), isFalse);
      expect(searches.last['recipient'], '%_literal');
      expect(searches.last['query'], '\ufeffNeedle\ufeff');
      expect(searches.last['tags'], ['\ufeffTag\ufeff']);
    }
    expect(DocumentSearchCriteria.validateAddress('😀' * 321), isNotNull);
    expect(DocumentSearchCriteria.validateAddress('\ud800'), isNotNull);
    expect(DocumentSearchCriteria.validateAddress('\udc00'), isNotNull);
  });

  for (final timeout in [false, true]) {
    test(
      '${timeout ? 'timeout' : 'consumer cancellation'} physically aborts generated transport without closing borrowed client',
      () async {
        final upstream = _PendingClient();
        final client = api.ApiClient(basePath: 'http://example.test')
          ..client.close();
        client.client = upstream;
        addTearDown(client.client.close);
        final source = DocumentVocabularyRemoteDataSource(
          api.DocumentsApi(client),
          timeout: Duration(milliseconds: timeout ? 20 : 1000),
        );
        final repository = RemoteDocumentVocabularyRepository(source);
        final cancel = Completer<void>();
        final future = repository.lookup(
          DocumentVocabularyField.tag,
          cancel: cancel.future,
        );
        final assertion = expectLater(
          future,
          _failure(
            timeout
                ? DocumentFailureKind.unavailable
                : DocumentFailureKind.cancelled,
          ),
        );
        await upstream.started.future;
        if (!timeout) cancel.complete();
        await assertion;
        await upstream.aborted.future.timeout(const Duration(seconds: 1));
        expect(upstream.closed, isFalse);
        source.cancelRequests();
        await expectLater(
          repository.lookup(DocumentVocabularyField.tag),
          _failure(DocumentFailureKind.cancelled),
        );
        expect(upstream.calls, 1);
      },
    );
  }

  test('streaming wrapper size failure through generated ApiException remains tooLarge', () async {
    final upstream = MockClient((_) async => http.Response('x' * 100, 200));
    final client = api.ApiClient(basePath: 'http://example.test')
      ..client.close();
    client.client = LimitedResponseClient(upstream, maximumBytes: 8);
    addTearDown(client.client.close);
    final repository = RemoteDocumentVocabularyRepository(
      DocumentVocabularyRemoteDataSource(api.DocumentsApi(client)),
    );
    await expectLater(
      repository.lookup(DocumentVocabularyField.tag),
      _failure(DocumentFailureKind.tooLarge),
    );
  });
}

final class _PendingClient extends http.BaseClient {
  final started = Completer<void>(), aborted = Completer<void>();
  bool closed = false;
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    final result = Completer<http.StreamedResponse>();
    expect(request, isA<http.Abortable>());
    (request as http.Abortable).abortTrigger!.then((_) {
      aborted.complete();
      result.completeError(http.RequestAbortedException(request.url));
    });
    started.complete();
    return result.future;
  }

  @override
  void close() => closed = true;
}
