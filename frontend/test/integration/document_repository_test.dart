import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/document/datasources/document_remote_data_source.dart';
import 'package:domabas/data/document/repos/remote_document_repository.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late api.ApiClient client;
  late RemoteDocumentRepository repository;
  late Future<void> Function(HttpRequest) respond;
  const id = 'c70a9c09-efcc-4210-830c-b73c408ac2ae';
  final document = <String, Object>{
    'id': id,
    'title': 'Invoice',
    'description': 'Paid',
    'createdAt': '2026-09-17T12:00:00Z',
  };

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}');
    repository = RemoteDocumentRepository(
      DocumentRemoteDataSource(api.DocumentsApi(client)),
    );
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      await respond(request);
      await request.response.close();
    });
  });
  tearDown(() async {
    client.client.close();
    await server.close(force: true);
  });

  test(
    'semantic pages accept an omitted total and retain continuation',
    () async {
      respond = (request) async {
        request.response.write(
          jsonEncode({
            'items': [
              {
                'document': {
                  'id': id,
                  'title': 'Invoice',
                  'kind': 'document',
                  'tags': <String>[],
                  'createdAt': '2026-09-17T12:00:00Z',
                },
                'snippet': 'Payment request',
                'score': 0.9,
              },
            ],
            'nextCursor': 'next-semantic-page',
          }),
        );
      };
      final page = await repository.search(
        DocumentSearchCriteria(query: 'payment'),
      );
      expect(page.total, isNull);
      expect(page.items.single.id, id);
      expect(page.nextCursor, 'next-semantic-page');
    },
  );

  for (final status in [400, 415, 422, 500, 503, 504]) {
    test('search HTTP $status reports a search failure without server details', () async {
      respond = (request) async {
        request.response.statusCode = status;
        request.response.write('{"message":"private deployment details"}');
      };
      await expectLater(
        repository.search(DocumentSearchCriteria(query: 'invoice')),
        throwsA(
          isA<DocumentFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                status >= 500
                    ? DocumentFailureKind.searchUnavailable
                    : DocumentFailureKind.searchRejected,
              )
              .having(
                (failure) => failure.message,
                'safe message',
                isNot(contains('private')),
              )
              .having(
                (failure) => failure.message,
                'does not misreport a server response as a connection failure',
                isNot(contains('could not reach')),
              ),
        ),
      );
    });
  }

  test(
    'AI retry transport sends its stable identity without retrying ingestion',
    () async {
      const requestId = '11111111-1111-4111-8111-111111111111';
      var calls = 0;
      respond = (request) async {
        calls++;
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/documents/$id/ai/retry');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'requestId': requestId,
          'configurationRevision': 3,
        });
        request.response.statusCode = 202;
        request.response.write(
          jsonEncode({
            'jobId': '22222222-2222-4222-8222-222222222222',
            'attempt': 2,
            'configurationRevision': 3,
            'status': 'queued',
            'stage': 'queued',
            'updatedAt': '2026-09-21T12:00:00Z',
          }),
        );
      };
      final result = await repository.retryAI(
        id,
        const DocumentAIRetryRequest(requestId, 3),
      );
      expect(calls, 1);
      expect(result.attempt, 2);
      expect(result.status, 'queued');
    },
  );

  test('real HTTP transport serializes create, paginates and maps detail to domain', () async {
    final calls = <String>[];
    respond = (request) async {
      calls.add('${request.method} ${request.uri.path}');
      if (request.method == 'POST') {
        expect(request.headers.contentType?.mimeType, 'application/json');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'title': 'Invoice',
          'description': 'Paid',
        });
        request.response.statusCode = 201;
        request.response.write(jsonEncode(document));
      } else if (request.uri.path.endsWith(id)) {
        request.response.write(jsonEncode(document));
      } else {
        expect(request.uri.queryParameters, {'limit': '25', 'offset': '5'});
        request.response.write(
          jsonEncode({
            'items': [document],
            'total': 6,
          }),
        );
      }
    };
    final created = await repository.create(
      DocumentDraft(title: 'Invoice', description: 'Paid'),
    );
    expect(created.id, id);
    final page = await repository.list(limit: 25, offset: 5);
    expect(page.total, 6);
    expect(page.items.single, isA<Document>());
    expect(
      (await repository.getById(id)).createdAt,
      DateTime.utc(2026, 9, 17, 12),
    );
    expect(calls, [
      'POST /api/v1/documents',
      'GET /api/v1/documents',
      'GET /api/v1/documents/$id',
    ]);
  });

  for (final status in [400, 404, 500]) {
    test('HTTP $status becomes a stable domain failure', () async {
      respond = (request) async {
        request.response.statusCode = status;
        request.response.write(
          jsonEncode({'code': 'internal', 'message': 'private server detail'}),
        );
      };
      final expected = switch (status) {
        400 => DocumentFailureKind.rejected,
        404 => DocumentFailureKind.notFound,
        _ => DocumentFailureKind.unavailable,
      };
      await expectLater(
        repository.getById(id),
        throwsA(
          isA<DocumentFailure>()
              .having((error) => error.kind, 'kind', expected)
              .having(
                (error) => error.message,
                'message',
                isNot(contains('private')),
              ),
        ),
      );
    });
  }

  for (final malformed in [
    'not-json',
    '{"id":"missing-required-fields"}',
    jsonEncode({...document, 'id': 'invalid'}),
    jsonEncode({...document, 'createdAt': 'not-a-date'}),
  ]) {
    test('malformed response is rejected: $malformed', () async {
      respond = (request) async => request.response.write(malformed);
      await expectLater(
        repository.getById(id),
        throwsA(
          isA<DocumentFailure>().having(
            (error) => error.kind,
            'kind',
            DocumentFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }

  test('bounded request maps a stalled server to unavailable', () async {
    repository = RemoteDocumentRepository(
      DocumentRemoteDataSource(
        api.DocumentsApi(client),
        timeout: const Duration(milliseconds: 30),
      ),
    );
    respond = (request) async =>
        Future<void>.delayed(const Duration(milliseconds: 100));
    await expectLater(
      repository.getById(id),
      throwsA(
        isA<DocumentFailure>().having(
          (error) => error.kind,
          'kind',
          DocumentFailureKind.unavailable,
        ),
      ),
    );
  });

  test('search has its own longer deadline', () async {
    repository = RemoteDocumentRepository(
      DocumentRemoteDataSource(
        api.DocumentsApi(client),
        timeout: const Duration(milliseconds: 10),
        searchTimeout: const Duration(seconds: 1),
      ),
    );
    respond = (request) async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      request.response.write('{"items":[]}');
    };
    final page = await repository.search(
      DocumentSearchCriteria(query: 'invoice payment'),
    );
    expect(page.items, isEmpty);
  });

  test('search still times out when its own deadline expires', () async {
    repository = RemoteDocumentRepository(
      DocumentRemoteDataSource(
        api.DocumentsApi(client),
        searchTimeout: const Duration(milliseconds: 30),
      ),
    );
    respond = (request) async =>
        Future<void>.delayed(const Duration(milliseconds: 100));
    await expectLater(
      repository.search(DocumentSearchCriteria(query: 'invoice payment')),
      throwsA(
        isA<DocumentFailure>().having(
          (error) => error.kind,
          'kind',
          DocumentFailureKind.unavailable,
        ),
      ),
    );
  });

  test(
    'search sends sparse JSON with Unicode tags and maps cursor summaries',
    () async {
      final calls = <Map<String, dynamic>>[];
      respond = (request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/documents/search');
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        calls.add(body);
        expect(body.values, isNot(contains(null)));
        request.response.write(
          jsonEncode({
            'items': [
              {
                'document': {
                  'id': id,
                  'title': 'İ Σ 😀',
                  'kind': 'email',
                  'tags': ['İ', 'Σ'],
                  'createdAt': '2026-09-18T12:00:00Z',
                },
                'snippet': 'Exact Unicode',
                'score': .5,
              },
            ],
            'total': 3,
            'nextCursor': 'continuation',
          }),
        );
      };
      final result = await repository.search(
        DocumentSearchCriteria(
          query: '  Invoice  ',
          tags: ['WORK', 'work', 'İ', 'ΟΣ'],
          kinds: [DocumentKind.letter, DocumentKind.document],
          sender: ' A%_ ',
          recipient: ' BCC ',
          sort: DocumentSort.title,
        ),
      );
      expect(result.nextCursor, 'continuation');
      expect(result.items.single.title, 'İ Σ 😀');
      expect(result.items.single.tags, ['İ', 'Σ']);
      expect(result.items.single.originalRef, isNull);
      expect(calls.single, {
        'query': 'Invoice',
        'mode': 'hybrid',
        'limit': 12,
        'sort': 'title',
        'tags': ['work', 'İ', 'ΟΣ'],
        'kinds': ['document', 'letter'],
        'sender': 'A%_',
        'recipient': 'BCC',
      });
      await repository.search(DocumentSearchCriteria(), cursor: 'continuation');
      expect(calls.last, {
        'query': '',
        'mode': 'hybrid',
        'limit': 12,
        'sort': 'newest',
        'cursor': 'continuation',
      });
      await repository.search(
        DocumentSearchCriteria(kinds: DocumentKind.values),
      );
      expect(calls.last.containsKey('kinds'), isFalse);
    },
  );

  test(
    'search originals retain identity without loading complete metadata',
    () async {
      final calls = <String>[];
      for (final media in [
        'image/png',
        'image/jpeg',
        'application/pdf',
        'message/rfc822',
      ]) {
        respond = (request) async {
          calls.add(request.uri.path);
          request.response.write(
            jsonEncode({
              'items': [
                {
                  'document': {
                    'id': id,
                    'title': 'Preview',
                    'kind': 'document',
                    'tags': <String>[],
                    'createdAt': '2026-09-18T12:00:00Z',
                    'original': {
                      'sha256': 'a' * 64,
                      'mediaType': media,
                      'size': 123,
                    },
                  },
                  'snippet': 'Bounded text',
                  'score': 1,
                },
              ],
              'total': 1,
            }),
          );
        };
        final page = await repository.search(
          DocumentSearchCriteria(query: 'preview'),
        );
        final original = page.items.single.originalRef!;
        expect(original.id, id);
        expect(original.original.sha256, 'a' * 64);
        expect(original.original.mediaType, media);
        expect(original.original.size, 123);
      }
      expect(calls, everyElement('/api/v1/documents/search'));
    },
  );

  for (final invalid in <Object?>[
    null,
    false,
    {},
    {'sha256': 'a' * 64, 'mediaType': 'image/png'},
    {'sha256': 'a' * 64, 'mediaType': 'image/png', 'size': 1.5},
    {'sha256': 'a' * 64, 'mediaType': 'image/png', 'size': '100'},
    {'sha256': 'a' * 64, 'mediaType': 'image/png', 'size': 0},
    {'sha256': 'a' * 64, 'mediaType': 'image/png', 'size': 104857601},
    {'sha256': 'A' * 64, 'mediaType': 'image/png', 'size': 100},
    {'sha256': 'short', 'mediaType': 'image/png', 'size': 100},
    {'sha256': 'a' * 64, 'mediaType': 'text/html', 'size': 100},
  ]) {
    test('malformed search original fails the page: $invalid', () async {
      respond = (request) async => request.response.write(
        jsonEncode({
          'items': [
            {
              'document': {
                'id': id,
                'title': 'Invalid preview',
                'kind': 'document',
                'tags': <String>[],
                'createdAt': '2026-09-18T12:00:00Z',
                'original': invalid,
              },
              'snippet': '',
              'score': 1,
            },
          ],
          'total': 1,
        }),
      );
      await expectLater(
        repository.search(DocumentSearchCriteria()),
        throwsA(
          isA<DocumentFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }

  test(
    'cancelling search leaves concurrent detail and later searches alive',
    () async {
      final searchStarted = Completer<void>();
      final releaseSearch = Completer<void>();
      final detailStarted = Completer<void>();
      final releaseDetail = Completer<void>();
      respond = (request) async {
        if (request.uri.path.endsWith('/search')) {
          if (!searchStarted.isCompleted) {
            searchStarted.complete();
            await releaseSearch.future;
          }
          request.response.write(jsonEncode({'items': <Object>[], 'total': 0}));
        } else {
          detailStarted.complete();
          await releaseDetail.future;
          request.response.write(jsonEncode(document));
        }
      };
      final cancel = Completer<void>();
      final search = repository.search(
        DocumentSearchCriteria(query: 'pending'),
        cancel: cancel.future,
      );
      final aborted = expectLater(search, throwsA(isA<DocumentFailure>()));
      final detail = repository.getById(id);
      await Future.wait([searchStarted.future, detailStarted.future]);
      cancel.complete();
      await aborted;
      releaseSearch.complete();
      releaseDetail.complete();
      expect((await detail).id, id);
      expect(
        (await repository.search(DocumentSearchCriteria(query: 'next'))).total,
        0,
      );
    },
  );
}
