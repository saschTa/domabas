import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/workload/datasources/workload_remote_data_source.dart';
import 'package:domabas/data/workload/repos/remote_workload_settings_repository.dart';
import 'package:domabas/domain/workload/models/workload_settings.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late api.ApiClient client;
  late RemoteWorkloadSettingsRepository repository;
  late Future<void> Function(HttpRequest) respond;
  final settings = <String, Object>{
    'revision': 3,
    'ollamaQueueSize': 128,
    'resources': [
      {
        'id': 'worker',
        'label': 'Worker',
        'limit': 4,
        'maximumLimit': 256,
        'activeJobs': 6,
      },
      {
        'id': 'ollama',
        'label': 'Ollama',
        'limit': 8,
        'maximumLimit': 64,
        'activeJobs': 1,
      },
      {
        'id': 'external:future-provider',
        'label': 'External provider',
        'limit': 2,
        'maximumLimit': 256,
        'activeJobs': 0,
      },
    ],
    'pipelines': [
      {
        'id': 'paperless',
        'label': 'Paperless retrieval',
        'resourceIds': ['worker'],
      },
      {
        'id': 'chat',
        'label': 'AI chat',
        'resourceIds': ['worker', 'external:future-provider'],
      },
    ],
  };
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}');
    repository = RemoteWorkloadSettingsRepository(
      WorkloadRemoteDataSource(api.SystemApi(client)),
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
    'generated client keeps dynamic resources and sends revisioned limits',
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
      expect(loaded.resources.first.activeJobs, 6);
      expect(loaded.pipelines.last.resourceIds, [
        'worker',
        'external:future-provider',
      ]);
      await repository.updateSettings(
        limits: {'worker': 5, 'ollama': 12, 'external:future-provider': 2},
        expectedRevision: loaded.revision,
      );
      expect(requests.map((r) => r.method), ['GET', 'PUT']);
      expect(
        requests.every((r) => r.path == '/api/v1/system/workload-settings'),
        isTrue,
      );
      expect(jsonDecode(requests.last.body), {
        'expectedRevision': 3,
        'resources': [
          {'id': 'worker', 'limit': 5},
          {'id': 'ollama', 'limit': 12},
          {'id': 'external:future-provider', 'limit': 2},
        ],
      });
    },
  );

  test(
    'unknown pipeline resource is rejected before entering presentation',
    () async {
      respond = (request) async {
        request.response.write(
          jsonEncode({
            ...settings,
            'pipelines': [
              {
                'id': 'chat',
                'label': 'AI chat',
                'resourceIds': ['missing'],
              },
            ],
          }),
        );
      };
      await expectLater(
        repository.settings(),
        throwsA(isA<WorkloadSettingsFailure>()),
      );
    },
  );

  for (final entry in {
    401: 'unauthorized',
    403: 'forbidden',
    409: 'conflict',
    503: 'unavailable',
  }.entries) {
    test('maps ${entry.key} without displaying server details', () async {
      respond = (request) async {
        request.response.statusCode = entry.key;
        request.response.write('{"message":"private upstream content"}');
      };
      await expectLater(
        repository.settings(),
        throwsA(
          isA<WorkloadSettingsFailure>()
              .having((failure) => failure.code, 'code', entry.value)
              .having(
                (failure) => failure.message.contains('private'),
                'private data',
                isFalse,
              ),
        ),
      );
    });
  }
}
