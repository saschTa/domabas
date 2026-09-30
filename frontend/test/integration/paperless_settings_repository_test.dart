import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/paperless/datasources/paperless_remote_data_source.dart';
import 'package:domabas/data/paperless/repos/remote_paperless_settings_repository.dart';
import 'package:domabas/domain/paperless/models/paperless_settings.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late api.ApiClient client;
  late RemotePaperlessSettingsRepository repository;
  late Future<void> Function(HttpRequest) respond;
  final settings = <String, Object>{
    'retrievalConcurrency': 4,
    'revision': 3,
    'minimumRetrievalConcurrency': 1,
    'maximumRetrievalConcurrency': 10,
  };

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}');
    repository = RemotePaperlessSettingsRepository(
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

  test(
    'generated client maps settings and sends revision-protected writes',
    () async {
      final requests = <({String method, String path, String body})>[];
      respond = (request) async {
        requests.add((
          method: request.method,
          path: request.uri.path,
          body: await utf8.decoder.bind(request).join(),
        ));
        request.response.write(jsonEncode(settings));
      };
      final loaded = await repository.settings();
      expect(loaded.retrievalConcurrency, 4);
      expect(loaded.revision, 3);
      expect(loaded.minimumRetrievalConcurrency, 1);
      expect(loaded.maximumRetrievalConcurrency, 10);
      await repository.updateSettings(
        retrievalConcurrency: 6,
        expectedRevision: 3,
      );
      expect(requests.map((r) => r.method), ['GET', 'PUT']);
      expect(
        requests.every((r) => r.path == '/api/v1/system/paperless-import'),
        isTrue,
      );
      expect(jsonDecode(requests.last.body), {
        'retrievalConcurrency': 6,
        'expectedRevision': 3,
      });
    },
  );

  for (final entry in {
    401: 'unauthorized',
    403: 'forbidden',
    409: 'conflict',
    503: 'unavailable',
  }.entries) {
    test('maps ${entry.key} without exposing server content', () async {
      respond = (request) async {
        request.response.statusCode = entry.key;
        request.response.write('{"message":"private upstream content"}');
      };
      await expectLater(
        repository.settings(),
        throwsA(
          isA<PaperlessSettingsFailure>()
              .having((f) => f.code, 'code', entry.value)
              .having(
                (f) => f.message.contains('private'),
                'private body',
                isFalse,
              ),
        ),
      );
    });
  }

  test('invalid settings do not enter the domain', () async {
    respond = (request) async {
      request.response.write(
        jsonEncode({...settings, 'retrievalConcurrency': 11}),
      );
    };
    await expectLater(
      repository.settings(),
      throwsA(isA<PaperlessSettingsFailure>()),
    );
  });
}
