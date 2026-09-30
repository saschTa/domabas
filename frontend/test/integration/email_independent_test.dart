import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/email/datasources/email_remote_data_source.dart';
import 'package:domabas/data/email/repos/remote_email_repository.dart';
import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/presentation/email/cubits/email_providers_cubit.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const namespace = '00000000-0000-4000-8000-000000000001';
  const providerId = '00000000-0000-4000-8000-000000000002';
  const runId = '00000000-0000-4000-8000-000000000003';
  const requestId = '00000000-0000-4000-8000-000000000004';
  const foreignId = '00000000-0000-4000-8000-000000000005';
  final run = <String, Object?>{
    'id': runId,
    'providerId': providerId,
    'namespaceId': namespace,
    'reason': 'manual',
    'status': 'queued',
    'stage': 'queued',
    'createdAt': '2026-09-18T12:00:00Z',
    'startedAt': null,
    'finishedAt': null,
    'failureCode': null,
    'messagesDiscovered': 0,
    'messagesAccepted': 0,
    'messagesReused': 0,
    'messagesSkipped': 0,
    'messagesFailed': 0,
    'messagesWithContentFailures': 0,
    'attachmentsAccepted': 0,
    'attachmentsReused': 0,
    'attachmentsSkipped': 0,
    'attachmentsFailed': 0,
    'hasMore': false,
  };
  late HttpServer server;
  late api.ApiClient client;
  late RemoteEmailRepository repository;
  late List<Map<String, Object?>> requests;
  late Map<String, Object?> responseMutation;
  var revision = 7, deleted = false;

  setUp(() async {
    requests = [];
    responseMutation = {};
    revision = 7;
    deleted = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}');
    repository = RemoteEmailRepository(
      EmailRemoteDataSource(api.EmailApi(client)),
      namespaceId: namespace,
    );
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      Object? body;
      if (request.uri.path == '/api/v1/email-capabilities') {
        body = {
          'credentialsAvailable': true,
          'unavailableReason': null,
          'transport': 'implicit_tls',
          'defaultIntervalMinutes': 15,
          'minIntervalMinutes': 5,
          'maxIntervalMinutes': 1440,
          'defaultMaxAgeDays': 30,
          'minMaxAgeDays': 1,
          'maxMaxAgeDays': 3650,
          'defaultPageSize': 50,
          'minPageSize': 1,
          'maxPageSize': 100,
          'maxProviders': 20,
        };
      } else if (request.uri.path == '/api/v1/email-runs') {
        expect(request.uri.queryParameters, {'limit': '20'});
        body = {
          'items': [
            {...run, ...responseMutation},
          ],
          'nextCursor': null,
        };
      } else if (request.uri.path.endsWith('/$providerId/runs')) {
        if (request.method == 'POST') {
          requests.add(
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, Object?>(),
          );
          request.response.statusCode = 202;
          body = {...run, ...responseMutation};
        } else {
          body = {
            'items': requests.isEmpty ? <Map<String, Object?>>[] : [run],
            'nextCursor': null,
          };
        }
      } else if (request.uri.path.endsWith('/$providerId')) {
        if (request.method == 'DELETE') {
          deleted = true;
          request.response.statusCode = 204;
        } else {
          body = {
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
            'revision': revision,
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
        }
      } else {
        request.response.statusCode = 404;
      }
      if (body != null) request.response.write(jsonEncode(body));
      await request.response.close();
    });
  });
  tearDown(() async {
    client.client.close();
    await server.close(force: true);
  });

  test('combined email history uses the collection endpoint and validates the library', () async {
    final page = await repository.listRuns(null);
    expect(page.items.single.id, runId);
    responseMutation = {'namespaceId': foreignId};
    await expectLater(repository.listRuns(null), throwsA(isA<EmailFailure>()));
  });

  test(
    'manual acknowledgment keeps distinct run and request identities',
    () async {
      final accepted = await repository.startRun(providerId, requestId, 7);
      final replayed = await repository.startRun(providerId, requestId, 7);
      expect(accepted.id, runId);
      expect(replayed.id, runId);
      expect(accepted.id, isNot(requestId));
      expect(requests, [
        {'requestId': requestId, 'expectedRevision': 7},
        {'requestId': requestId, 'expectedRevision': 7},
      ]);
    },
  );

  for (final mutation in [
    {'providerId': foreignId},
    {'namespaceId': foreignId},
    {'reason': 'scheduled'},
  ]) {
    test(
      'manual acknowledgment rejects ${mutation.keys.single} mismatch',
      () async {
        responseMutation = mutation;
        await expectLater(
          repository.startRun(providerId, requestId, 7),
          throwsA(
            isA<EmailFailure>().having(
              (failure) => failure.kind,
              'response validation',
              EmailFailureKind.invalidResponse,
            ),
          ),
        );
      },
    );
  }

  Future<EmailProvidersCubit> selectedCubit() async {
    final cubit = EmailProvidersCubit(
      repository,
      allowed: true,
      canImport: true,
    );
    addTearDown(cubit.close);
    await cubit.select(providerId);
    return cubit;
  }

  Future<void> activate(EmailProvidersCubit cubit) async {
    cubit.setActive(true);
    if (cubit.state.loading) {
      await cubit.stream
          .firstWhere((state) => !state.loading)
          .timeout(const Duration(seconds: 3));
    }
  }

  test('accepted manual import clears pending and permits delete after reactivation', () async {
    final cubit = await selectedCubit();
    await activate(cubit);
    await cubit.importNow();
    expect(cubit.state.pendingRun, isFalse);
    expect(cubit.state.saving, isFalse);
    expect(cubit.state.error, isNull);
    expect(cubit.state.runs.single.id, runId);
    expect(requests.single['requestId'], isNot(runId));
    expect(requests.single['expectedRevision'], 7);
    cubit.setActive(false);
    await activate(cubit);
    expect(cubit.state.pendingRun, isFalse);
    expect(cubit.state.saving, isFalse);
    expect(cubit.state.loading, isFalse);
    await cubit.deleteProvider();
    expect(deleted, isTrue);
    expect(cubit.state.provider, isNull);
    expect(cubit.state.saving, isFalse);
  });

  test('uncertain response replay preserves request and revision after fresh provider read', () async {
    final cubit = await selectedCubit();
    responseMutation = {'namespaceId': foreignId};
    await cubit.importNow();
    expect(cubit.state.pendingRun, isTrue);
    expect(cubit.state.saving, isFalse);
    responseMutation = {};
    revision = 8;
    await cubit.load();
    expect(cubit.state.provider?.revision, 8);
    await cubit.importNow(retry: true);
    expect(requests, hasLength(2));
    expect(requests.last, requests.first);
    expect(requests.last['expectedRevision'], 7);
    expect(cubit.state.pendingRun, isFalse);
    expect(cubit.state.saving, isFalse);
    expect(cubit.state.error, isNull);
    expect(cubit.state.runs.single.id, runId);
  });
}
