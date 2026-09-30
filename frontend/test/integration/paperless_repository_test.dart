import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/paperless/datasources/paperless_remote_data_source.dart';
import 'package:domabas/data/paperless/repos/remote_paperless_repository.dart';
import 'package:domabas/domain/paperless/models/paperless.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = '11111111-1111-4111-8111-111111111111';
  final run = <String, Object?>{
    'id': id,
    'serverUrl': 'https://paperless.example.test',
    'state': 'queued',
    'stage': 'queued',
    'discovered': 0,
    'imported': 0,
    'duplicates': 0,
    'failed': 0,
    'cancelRequested': false,
    'createdAt': '2026-09-19T00:00:00Z',
    'updatedAt': '2026-09-19T00:00:00Z',
    'outcomes': [],
  };
  late HttpServer server;
  late api.ApiClient client;
  late RemotePaperlessRepository repository;
  late Future<void> Function(HttpRequest) respond;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}');
    repository = RemotePaperlessRepository(
      PaperlessRemoteDataSource(api.PaperlessApi(client)),
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
  test('server totals are exact and missing summaries stay unknown', () async {
    respond = (request) async {
      request.response.write(
        jsonEncode({
          'items': <Object?>[],
          'nextCursor': null,
          'counts': {
            'groups': [
              {'status': 'failed', 'count': 123456},
            ],
          },
        }),
      );
    };
    final page = await repository.runs();
    expect(page.items, isEmpty);
    expect(page.counts?['failed'], 123456);
    respond = (request) async {
      request.response.write(
        jsonEncode({'items': <Object?>[], 'nextCursor': null}),
      );
    };
    expect((await repository.runs()).counts, isNull);
  });

  test(
    'generated pagination sends bounded cursors and maps outcomes',
    () async {
      final requests = <Uri>[];
      respond = (request) async {
        requests.add(request.uri);
        request.response.write(
          jsonEncode(
            request.uri.path.endsWith('/outcomes')
                ? {
                    'items': [
                      {'sourceId': 101, 'title': 'Result', 'status': 'failed'},
                    ],
                    'nextCursor': 'next-results',
                  }
                : {
                    'items': [run],
                    'nextCursor': 'next-runs',
                  },
          ),
        );
      };
      final page = await repository.runs(
        limit: 10,
        cursor: 'older+/=',
        status: 'succeeded',
      );
      expect(page.items.single.id, id);
      expect(page.nextCursor, 'next-runs');
      final outcomes = await repository.outcomes(
        id,
        limit: 10,
        cursor: 'older-results',
        status: 'failed',
      );
      expect(outcomes.items.single.sourceId, 101);
      expect(outcomes.nextCursor, 'next-results');
      expect(requests.first.queryParameters, {
        'limit': '10',
        'cursor': 'older+/=',
        'status': 'succeeded',
      });
      expect(requests.last.path, '/api/v1/paperless-import/runs/$id/outcomes');
      expect(requests.last.queryParameters, {
        'limit': '10',
        'cursor': 'older-results',
        'status': 'failed',
      });
      await expectLater(
        repository.runs(cursor: 'next-runs'),
        throwsA(isA<PaperlessFailure>()),
      );
    },
  );
  test(
    'options need no operator-provided servers or credential flags',
    () async {
      respond = (request) async {
        request.response.write('{"pageSize":100}');
      };
      expect((await repository.options()).pageSize, 100);
    },
  );
  test('generated requests send a private token only in the start body and match run identities', () async {
    final bodies = <String>[];
    final paths = <String>[];
    respond = (request) async {
      bodies.add(await utf8.decoder.bind(request).join());
      paths.add(request.uri.toString());
      request.response.statusCode =
          request.method == 'POST' && !request.uri.path.endsWith('/cancel')
          ? 202
          : 200;
      request.response.write(jsonEncode(run));
    };
    final created = await repository.start(
      id,
      const PaperlessConnection(
        serverUrl: 'https://paperless.example.test',
        token: 'sensitive-fixture-token',
      ),
    );
    expect(created.id, id);
    expect(jsonDecode(bodies.first), {
      'requestId': id,
      'serverUrl': 'https://paperless.example.test',
      'token': 'sensitive-fixture-token',
    });
    await repository.get(id);
    await repository.cancelRun(id);
    expect(bodies.skip(1), everyElement(isEmpty));
    expect(paths, everyElement(isNot(contains('sensitive-fixture-token'))));
  });
  test(
    'malformed receipts are uncertain and never expose remote bodies',
    () async {
      for (final mutation in <Map<String, Object?>>[
        {'id': 'other'},
        {'state': 'unknown'},
        {'discovered': -1},
        {'imported': 1},
      ]) {
        respond = (request) async {
          request.response.write(jsonEncode({...run, ...mutation}));
        };
        await expectLater(
          repository.get(id),
          throwsA(
            isA<PaperlessFailure>().having(
              (e) => e.uncertain,
              'uncertain',
              true,
            ),
          ),
        );
      }
      respond = (request) async {
        request.response.statusCode = 503;
        request.response.write('private server token');
      };
      try {
        await repository.get(id);
        fail('failure expected');
      } on PaperlessFailure catch (e) {
        expect(e.message, isNot(contains('private server token')));
        expect(e.uncertain, isTrue);
      }
      respond = (request) async {
        request.response.statusCode = 502;
        request.response.write(
          '{"code":"proxy_error","message":"private server token"}',
        );
      };
      await expectLater(
        repository.start(
          id,
          const PaperlessConnection(
            serverUrl: 'https://paperless.example.test',
            token: 'fixture-token',
          ),
        ),
        throwsA(
          isA<PaperlessFailure>().having(
            (e) => e.uncertain,
            'uncertain proxy receipt',
            true,
          ),
        ),
      );
    },
  );
  test('progress above ten thousand documents remains readable', () async {
    respond = (request) async {
      request.response.write(
        jsonEncode({...run, 'discovered': 25000, 'imported': 12000}),
      );
    };
    final progress = await repository.get(id);
    expect(progress.discovered, 25000);
    expect(progress.imported, 12000);
  });
  test('scope cancellation aborts an in-flight generated request', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    respond = (request) async {
      entered.complete();
      await release.future;
    };
    final request = repository.get(id);
    final assertion = expectLater(
      request,
      throwsA(
        isA<PaperlessFailure>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    await entered.future;
    repository.cancelRequests();
    await assertion;
    release.complete();
  });
}
