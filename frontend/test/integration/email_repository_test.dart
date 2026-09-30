import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/email/datasources/email_remote_data_source.dart';
import 'package:domabas/data/email/repos/remote_email_repository.dart';
import 'package:domabas/data/identity/datasources/personal_activity_remote_data_source.dart';
import 'package:domabas/data/identity/repos/remote_personal_activity_repository.dart';
import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/domain/identity/models/personal_activity.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const namespace = '00000000-0000-4000-8000-000000000001';
  const providerId = '00000000-0000-4000-8000-000000000002';
  final provider = <String, Object?>{
    'id': providerId,
    'namespaceId': namespace,
    'label': 'Mailbox',
    'host': 'imap.example.test',
    'port': 993,
    'mailbox': 'INBOX',
    'intervalMinutes': 15,
    'maxAgeDays': 30,
    'pageSize': 50,
    'enabled': true,
    'revision': 1,
    'sourceGeneration': 1,
    'credentialState': 'ready',
    'consentState': 'valid',
    'createdAt': '2026-09-18T12:00:00Z',
    'updatedAt': '2026-09-18T12:00:00Z',
    'lastAttemptAt': null,
    'nextDueAt': null,
    'activeRunId': null,
    'lastRunStatus': null,
    'failureCode': null,
    'username': 'owner@example.test',
    'hasPassword': true,
  };
  late HttpServer server;
  late api.ApiClient client;
  late RemoteEmailRepository repository;
  late Future<void> Function(HttpRequest) respond;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}');
    repository = RemoteEmailRepository(
      EmailRemoteDataSource(api.EmailApi(client)),
      namespaceId: namespace,
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
    final page = await repository.listRuns(null);
    expect(page.items, isEmpty);
    expect(page.counts?['failed'], 123456);
    respond = (request) async {
      request.response.write(
        jsonEncode({'items': <Object?>[], 'nextCursor': null}),
      );
    };
    expect((await repository.listRuns(null)).counts, isNull);
  });

  test('job status and cursor reach both email history endpoints', () async {
    final requests = <Uri>[];
    respond = (request) async {
      requests.add(request.uri);
      request.response.write(
        jsonEncode({'items': <Object?>[], 'nextCursor': null}),
      );
    };
    for (final provider in [null, providerId]) {
      await repository.listRuns(
        provider,
        status: 'failed',
        cursor: 'older+/=',
        limit: 10,
      );
      expect(
        requests.last.path,
        provider == null
            ? '/api/v1/email-runs'
            : '/api/v1/email-providers/$provider/runs',
      );
      expect(requests.last.queryParameters, {
        'status': 'failed',
        'cursor': 'older+/=',
        'limit': '10',
      });
    }
  });

  test('generated transport omits unchanged credentials and sends explicit consent intent', () async {
    final bodies = <Map<String, Object?>>[];
    respond = (request) async {
      if (request.method != 'GET') {
        bodies.add(
          (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
              .cast<String, Object?>(),
        );
      }
      request.response.write(jsonEncode(provider));
    };
    final saved = await repository.getProvider(providerId);
    await repository.updateProvider(
      saved,
      EmailProviderDraft.fromProvider(saved),
    );
    expect(bodies.single.containsKey('password'), isFalse);
    expect(bodies.single.containsKey('username'), isFalse);
    expect(bodies.single['renewConsent'], false);
    expect(bodies.single['expectedRevision'], 1);
    await repository.updateProvider(
      saved,
      EmailProviderDraft.fromProvider(saved)
          .copyWith(password: 'new-fixture-password'),
      renewConsent: true,
    );
    expect(bodies.last['password'], 'new-fixture-password');
    expect(bodies.last['renewConsent'], true);
  });

  test(
    'provider namespace mismatch and malformed credential state are rejected',
    () async {
      for (final mutation in [
        <String, Object?>{'namespaceId': providerId},
        <String, Object?>{'credentialState': 'unexpected'},
      ]) {
        respond = (request) async {
          request.response.write(jsonEncode({...provider, ...mutation}));
        };
        await expectLater(
          repository.getProvider(providerId),
          throwsA(
            isA<EmailFailure>().having(
              (value) => value.kind,
              'kind',
              EmailFailureKind.invalidResponse,
            ),
          ),
        );
      }
    },
  );

  test(
    'connection testing sends saved identity and never an empty password',
    () async {
      Map<String, Object?>? body;
      respond = (request) async {
        if (request.method == 'GET') {
          request.response.write(jsonEncode(provider));
          return;
        }
        body = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
            .cast<String, Object?>();
        request.response.write(
          jsonEncode({
            'success': true,
            'checkedAt': '2026-09-18T12:00:00Z',
            'failureCode': null,
          }),
        );
      };
      final saved = await repository.getProvider(providerId);
      expect(
        (await repository.testConnection(
          EmailProviderDraft.fromProvider(saved),
          provider: saved,
        )).success,
        isTrue,
      );
      expect(body!['providerId'], providerId);
      expect(body!['expectedRevision'], 1);
      expect(body!.containsKey('password'), isFalse);
    },
  );

  test('request deadline is an uncertain failure; explicit cancellation is distinct', () async {
    final requests = <Completer<void>>[];
    respond = (request) async {
      final release = Completer<void>();
      requests.add(release);
      await release.future;
      request.response.write(jsonEncode(provider));
    };
    addTearDown(() {
      for (final release in requests) {
        if (!release.isCompleted) release.complete();
      }
    });
    repository = RemoteEmailRepository(
      EmailRemoteDataSource(
        api.EmailApi(client),
        timeout: const Duration(milliseconds: 40),
      ),
      namespaceId: namespace,
    );
    await expectLater(
      repository.getProvider(providerId),
      throwsA(
        isA<EmailFailure>().having(
          (value) => value.uncertain,
          'uncertain outcome',
          true,
        ),
      ),
    );
    final cancel = Completer<void>();
    repository = RemoteEmailRepository(
      EmailRemoteDataSource(api.EmailApi(client)),
      namespaceId: namespace,
    );
    final result = repository.getProvider(providerId, cancel: cancel.future);
    cancel.complete();
    await expectLater(
      result,
      throwsA(
        isA<EmailFailure>().having(
          (value) => value.kind,
          'cancel',
          EmailFailureKind.cancelled,
        ),
      ),
    );
  });

  test(
    'private feed rejects invalid global finish ordering across job kinds',
    () async {
      Map<String, Object?> item(String id, String kind, String finished) => {
        'id': id,
        'kind': kind,
        'namespaceId': namespace,
        'namespaceName': 'Library',
        'status': 'succeeded',
        'stage': 'complete',
        'createdAt': '2026-09-18T10:00:00Z',
        'startedAt': null,
        'finishedAt': finished,
        'documentId': null,
        'providerId': null,
        'batchId': null,
        'title': null,
        'failureCode': null,
        'canOpen': false,
      };
      final activity = RemotePersonalActivityRepository(
        PersonalActivityRemoteDataSource(api.IdentityApi(client)),
      );
      respond = (request) async {
        request.response.write(
          jsonEncode({
            'active': <Object>[],
            'finished': [
              item(providerId, 'email_retrieval', '2026-09-18T11:00:00Z'),
              item(namespace, 'document_processing', '2026-09-18T12:00:00Z'),
            ],
            'activeLimit': 20,
            'activeTruncated': false,
            'generatedAt': '2026-09-18T12:01:00Z',
          }),
        );
      };
      await expectLater(
        activity.getActivity(),
        throwsA(
          isA<ActivityFailure>().having(
            (value) => value.kind,
            'ordering',
            ActivityFailureKind.invalidResponse,
          ),
        ),
      );
    },
  );
}
