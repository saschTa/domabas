import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/document/datasources/document_processing_remote_data_source.dart';
import 'package:domabas/data/document/repos/remote_document_processing_repository.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late api.ApiClient client;
  late RemoteDocumentProcessingRepository repository;
  late Future<void> Function(HttpRequest) respond;
  final snapshot = <String, Object?>{
    'revision': 1,
    'language': 'eng+deu',
    'segmentation': 'auto',
    'ocrEngine': 'tesseract',
    'ocrVersion': '5.5.3',
    'ocrModel': 'tessdata_fast',
    'ocrWeights': [
      {'name': 'eng', 'sha256': 'c' * 64},
    ],
    'embeddingModel': 'nomic-embed-text:v1.5',
    'embeddingDigest': 'a' * 64,
    'embeddingDimensions': 768,
    'fingerprint': 'b' * 64,
    'manifestRevision': 1,
    'extractionRevision': '1',
    'chunkingRevision': '1',
    'embeddingInputRevision': '1',
    'indexingRevision': '1',
  };
  final configuration = <String, Object?>{
    ...snapshot,
    'ready': true,
    'languages': ['eng', 'deu', 'eng+deu'],
    'segmentations': ['auto', 'single_block'],
    'dashboardUrl': 'https://temporal.internal/ui',
    'automaticBatchId': null,
  };
  final scheduling = <String, Object?>{
    'ingestionConcurrency': 5,
    'aiConcurrency': 2,
    'ollamaQueueSize': 11,
    'ingestionConcurrencyMode': 'ollama_half_queue',
    'aiConcurrencyMode': 'fixed',
    'providerStepRetries': 4,
    'priorityPolicy': 'ingestion_first',
  };

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}');
    repository = RemoteDocumentProcessingRepository(
      DocumentProcessingRemoteDataSource(api.DocumentsApi(client)),
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
    'active job and batch requests use server totals and scoped endpoints',
    () async {
      final paths = <String>[];
      respond = (request) async {
        expect(request.uri.queryParameters['activeOnly'], 'true');
        paths.add(request.uri.path);
        request.response.write(
          jsonEncode({
            'items': <Object?>[],
            'nextCursor': null,
            'counts': {
              'groups': [
                {
                  'status': 'running',
                  'count': 1000,
                  if (request.uri.path.endsWith('/document-jobs'))
                    'pipeline': 'ai',
                },
              ],
            },
          }),
        );
      };
      expect((await repository.listJobs(activeOnly: true)).counts, {
        ('ai', 'running'): 1000,
      });
      expect((await repository.listNamespaceBatches(activeOnly: true)).counts, {
        'running': 1000,
      });
      expect((await repository.listSystemBatches(activeOnly: true)).counts, {
        'running': 1000,
      });
      expect(paths, [
        '/api/v1/document-jobs',
        '/api/v1/document-reindex-batches',
        '/api/v1/system/document-reindex-batches',
      ]);
    },
  );

  test('thumbnail history maps without ingestion fields and validates render identity', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    final thumbnail = <String, Object?>{
      'id': id,
      'documentId': '22222222-2222-4222-8222-222222222222',
      'documentTitle': 'Preview source',
      'pipeline': 'thumbnail',
      'pipelineVersion': 1,
      'attempt': 2,
      'rendererRevision': 1,
      'reason': 'retry',
      'status': 'failed',
      'stage': 'rendering',
      'createdAt': '2026-09-24T12:00:00Z',
      'updatedAt': '2026-09-24T12:00:10Z',
      'startedAt': '2026-09-24T12:00:01Z',
      'finishedAt': '2026-09-24T12:00:10Z',
      'failureCode': 'invalid_file',
      'extractionMethod': null,
      'isCurrent': true,
      'documentDeleted': false,
    };
    respond = (request) async {
      expect(request.uri.queryParameters['pipeline'], 'thumbnail');
      request.response.write(
        jsonEncode({
          'items': [thumbnail],
          'nextCursor': 'older-thumbnails',
          'counts': {
            'groups': [
              {'pipeline': 'thumbnail', 'status': 'failed', 'count': 17},
            ],
          },
        }),
      );
    };
    final page = await repository.listJobs(pipeline: 'thumbnail');
    final job = page.items.single;
    expect(job.pipelineLabel, 'Thumbnail generation');
    expect(job.attemptNumber, 2);
    expect(job.rendererRevision, 1);
    expect(job.configuration, isNull);
    expect(job.generation, isNull);
    expect(job.textSource, isNull);
    expect(page.counts?[('thumbnail', 'failed')], 17);
    expect(page.nextCursor, 'older-thumbnails');
    respond = (request) async => request.response.write(jsonEncode(thumbnail));
    expect((await repository.getJob(id)).failureCode, 'invalid_file');
    for (final invalid in [
      {...thumbnail}..remove('attempt'),
      {...thumbnail, 'rendererRevision': 0},
      {...thumbnail, 'pipeline': 'ingestion'},
    ]) {
      respond = (request) async => request.response.write(jsonEncode(invalid));
      await expectLater(
        repository.getJob(id),
        throwsA(isA<DocumentProcessingFailure>()),
      );
    }
  });

  test(
    'pipeline model context uses its own route and rejects mismatched metadata',
    () async {
      const model = 'publisher/model:latest';
      respond = (request) async {
        expect(
          request.uri.path,
          '/api/v1/system/document-processing/model-context',
        );
        expect(request.uri.queryParameters, {'model': model});
        request.response.write(
          jsonEncode({'model': model, 'maxContextLength': 8192}),
        );
      };
      expect((await repository.modelContext(model)).maxContextLength, 8192);
      for (final invalid in [
        {'model': 'different', 'maxContextLength': 8192},
        {'model': model, 'maxContextLength': 0},
      ]) {
        respond = (request) async =>
            request.response.write(jsonEncode(invalid));
        await expectLater(
          repository.modelContext(model),
          throwsA(isA<DocumentProcessingFailure>()),
        );
      }
    },
  );

  test(
    'scheduling maps server limits and sources in namespace and admin reads',
    () async {
      respond = (request) async {
        request.response.write(
          jsonEncode({
            if (request.uri.path.contains('/system/'))
              ...configuration
            else ...{
              'configuration': snapshot,
              'ready': true,
              'languages': ['eng+deu'],
              'segmentations': ['auto'],
            },
            'scheduling': scheduling,
          }),
        );
      };
      for (final policy in [
        (await repository.getNamespacePipeline()).scheduling,
        (await repository.getSystemConfiguration()).pipeline.scheduling,
      ]) {
        expect(policy?.ingestionConcurrency, 5);
        expect(policy?.aiConcurrency, 2);
        expect(policy?.ollamaQueueSize, 11);
        expect(policy?.ingestionConcurrencyMode, 'ollama_half_queue');
        expect(policy?.aiConcurrencyMode, 'fixed');
        expect(policy?.providerStepRetries, 4);
        expect(policy?.priorityPolicy, 'ingestion_first');
      }
    },
  );

  test(
    'absent scheduling stays unknown and invalid capacity is rejected',
    () async {
      respond = (request) async =>
          request.response.write(jsonEncode(configuration));
      expect(
        (await repository.getSystemConfiguration()).pipeline.scheduling,
        isNull,
      );
      respond = (request) async => request.response.write(
        jsonEncode({
          ...configuration,
          'scheduling': {...scheduling, 'ingestionConcurrency': 0},
        }),
      );
      await expectLater(
        repository.getSystemConfiguration(),
        throwsA(
          isA<DocumentProcessingFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentProcessingFailureKind.invalidResponse,
          ),
        ),
      );
    },
  );

  test(
    'job matrices map exact totals and absent summaries stay unknown',
    () async {
      respond = (request) async {
        request.response.write(
          jsonEncode({
            'items': <Object?>[],
            'nextCursor': null,
            'counts': {
              'groups': [
                {'pipeline': 'ingestion', 'status': 'failed', 'count': 123456},
                {'pipeline': 'ai', 'status': 'failed', 'count': 4},
              ],
            },
          }),
        );
      };
      final page = await repository.listJobs();
      expect(page.counts, {
        ('ingestion', 'failed'): 123456,
        ('ai', 'failed'): 4,
      });
      respond = (request) async {
        request.response.write(
          jsonEncode({'items': <Object?>[], 'nextCursor': null}),
        );
      };
      expect((await repository.listJobs()).counts, isNull);
    },
  );

  test('real generated transport preserves sparse legacy and revision-checked settings requests', () async {
    final bodies = <Object?>[];
    respond = (request) async {
      expect(request.method, 'PUT');
      expect(request.uri.path, '/api/v1/system/document-processing');
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response.write(jsonEncode(configuration));
    };
    final legacy = await repository.updateSystemConfiguration(
      language: 'eng+deu',
      segmentation: 'auto',
    );
    expect(legacy.pipeline.configuration.fingerprint, 'b' * 64);
    expect(legacy.dashboardUrl, Uri.parse('https://temporal.internal/ui'));
    await repository.updateSystemConfiguration(
      language: 'eng+deu',
      segmentation: 'auto',
      expectedRevision: 1,
    );
    expect(bodies, [
      {'language': 'eng+deu', 'segmentation': 'auto'},
      {'language': 'eng+deu', 'segmentation': 'auto', 'expectedRevision': 1},
    ]);
  });

  test('timer-triggered HTTP abort is unavailable, while caller abort is cancelled', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    respond = (request) async {
      if (!received.isCompleted) received.complete();
      await release.future;
      request.response.write(jsonEncode(configuration));
    };
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    repository = RemoteDocumentProcessingRepository(
      DocumentProcessingRemoteDataSource(
        api.DocumentsApi(client),
        timeout: const Duration(milliseconds: 40),
      ),
    );
    await expectLater(
      repository.getSystemConfiguration(),
      throwsA(
        isA<DocumentProcessingFailure>().having(
          (value) => value.kind,
          'timeout',
          DocumentProcessingFailureKind.unavailable,
        ),
      ),
    );
    await received.future;
    final cancel = Completer<void>();
    repository = RemoteDocumentProcessingRepository(
      DocumentProcessingRemoteDataSource(api.DocumentsApi(client)),
    );
    final pending = repository.getSystemConfiguration(cancel: cancel.future);
    final assertion = expectLater(
      pending,
      throwsA(
        isA<DocumentProcessingFailure>().having(
          (value) => value.kind,
          'caller abort',
          DocumentProcessingFailureKind.cancelled,
        ),
      ),
    );
    cancel.complete();
    await assertion;
    release.complete();
  });

  test('generated extraction transport preserves omitted keys and maps only safe read fields', () async {
    final writes = <Map<String, dynamic>>[];
    respond = (request) async {
      expect(request.method, 'PUT');
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      writes.add(body['llm'] as Map<String, dynamic>);
      request.response.write(
        jsonEncode({
          ...configuration,
          'llm': {
            'enabled': true,
            'invoiceEnabled': false,
            'lmStudioCompatibility': writes.last['lmStudioCompatibility'],
            'provider': 'openai',
            'model': 'custom',
            'baseUrl': 'https://models.example/v1',
            'credentialConfigured': true,
            'contextLength': 16384,
          },
        }),
      );
    };
    const draft = DocumentLLMSettingsDraft(
      enabled: true,
      contextLength: '16384',
      provider: 'openai',
      model: 'custom',
      baseUrl: 'https://models.example/v1',
    );
    final saved = await repository.updateSystemConfiguration(
      language: 'eng+deu',
      segmentation: 'auto',
      expectedRevision: 1,
      llm: draft,
    );
    expect(writes.single.containsKey('apiKey'), isFalse);
    expect(writes.single['provider'], 'openai');
    expect(writes.single['contextLength'], 16384);
    expect(saved.llm.contextLength, 16384);
    expect(saved.llm.credentialConfigured, isTrue);
    expect(saved.pipeline.configuration.propertyExtractionEnabled, isTrue);
    expect(saved.pipeline.configuration.propertyExtractionModel, 'custom');
    expect(writes.single['invoiceEnabled'], isFalse);
    expect(saved.llm.invoiceEnabled, isFalse);
    expect(writes.single['lmStudioCompatibility'], isFalse);
    expect(saved.llm.lmStudioCompatibility, isFalse);
    expect(saved.pipeline.configuration.invoiceExtractionEnabled, isFalse);
    expect(saved.pipeline.configuration.invoiceExtractionModel, 'custom');
    final compatible = await repository.updateSystemConfiguration(
      language: 'eng+deu',
      segmentation: 'auto',
      llm: draft.copyWith(
        enabled: false,
        invoiceEnabled: true,
        lmStudioCompatibility: true,
      ),
    );
    expect(writes.last['enabled'], isFalse);
    expect(writes.last['invoiceEnabled'], isTrue);
    expect(writes.last['lmStudioCompatibility'], isTrue);
    expect(compatible.llm.lmStudioCompatibility, isTrue);
    await repository.updateSystemConfiguration(
      language: 'eng+deu',
      segmentation: 'auto',
      llm: draft.copyWith(apiKey: 'replacement-secret'),
    );
    expect(writes.last['apiKey'], 'replacement-secret');
    await repository.updateSystemConfiguration(
      language: 'eng+deu',
      segmentation: 'auto',
      llm: draft.copyWith(clearApiKey: true),
    );
    expect(writes.last['clearApiKey'], isTrue);
    expect(writes.last.containsKey('apiKey'), isFalse);
    await repository.updateSystemConfiguration(
      language: 'eng+deu',
      segmentation: 'auto',
      llm: draft.copyWith(
        provider: 'ollama',
        lmStudioCompatibility: true,
        apiKey: 'not-for-local',
        baseUrl: 'https://old.example/v1',
      ),
    );
    expect(writes.last['baseUrl'], isEmpty);
    expect(writes.last['lmStudioCompatibility'], isTrue);
    expect(writes.last.containsKey('apiKey'), isFalse);
    await repository.updateSystemConfiguration(
      language: 'eng+deu',
      segmentation: 'auto',
      llm: draft.copyWith(contextLength: ''),
    );
    expect(writes.last.containsKey('contextLength'), isFalse);
  });

  test('older extraction settings default optional thinking and compatibility to off', () async {
    respond = (request) async => request.response.write(
      jsonEncode({
        ...configuration,
        'llm': {
          'enabled': true,
          'invoiceEnabled': false,
          'provider': 'openai',
          'model': 'custom',
          'baseUrl': 'http://127.0.0.1:1234/v1',
          'credentialConfigured': false,
          'contextLength': 32768,
        },
      }),
    );
    final settings = (await repository.getSystemConfiguration()).llm;
    expect(settings.lmStudioCompatibility, isFalse);
    expect(settings.propertyThinkingEnabled, isFalse);
    expect(settings.invoiceThinkingEnabled, isFalse);
  });

  test('extraction thinking transport sends independent explicit on and off values', () async {
    for (final choices in [(true, false), (false, true)]) {
      respond = (request) async {
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        final llm = body['llm'] as Map<String, dynamic>;
        expect(llm['propertyThinkingEnabled'], choices.$1);
        expect(llm['invoiceThinkingEnabled'], choices.$2);
        request.response.write(
          jsonEncode({
            ...configuration,
            'llm': {...llm, 'credentialConfigured': false},
          }),
        );
      };
      final saved = await repository.updateSystemConfiguration(
        language: 'eng+deu',
        segmentation: 'auto',
        llm: DocumentLLMSettingsDraft(
          propertyThinkingEnabled: choices.$1,
          invoiceThinkingEnabled: choices.$2,
        ),
      );
      expect(saved.llm.propertyThinkingEnabled, choices.$1);
      expect(saved.llm.invoiceThinkingEnabled, choices.$2);
    }
  });

  test('invalid extraction settings fail as an invalid response without exposing their body', () async {
    respond = (request) async => request.response.write(
      jsonEncode({
        ...configuration,
        'llm': {
          'enabled': true,
          'invoiceEnabled': false,
          'lmStudioCompatibility': false,
          'provider': 'openai',
          'model': 'custom',
          'baseUrl': 'https://private-key@example.com/v1',
          'credentialConfigured': true,
          'contextLength': 32768,
        },
      }),
    );
    await expectLater(
      repository.getSystemConfiguration(),
      throwsA(
        isA<DocumentProcessingFailure>().having(
          (failure) => failure.kind,
          'kind',
          DocumentProcessingFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test(
    'namespace pipeline and pages keep opaque cursor filters at HTTP boundary',
    () async {
      respond = (request) async {
        if (request.uri.path.endsWith('/document-processing')) {
          request.response.write(
            jsonEncode({
              'configuration': snapshot,
              'ready': true,
              'languages': ['eng+deu'],
              'segmentations': ['auto'],
            }),
          );
        } else {
          expect(request.uri.queryParameters, {
            'limit': '10',
            'cursor': 'opaque+/=',
            'status': 'failed',
            'pipeline': 'ai',
          });
          request.response.write(
            jsonEncode({'items': <Object>[], 'nextCursor': null}),
          );
        }
      };
      expect(
        (await repository.getNamespacePipeline())
            .configuration
            .weights
            .single
            .name,
        'eng',
      );
      expect(
        (await repository.listJobs(
          limit: 10,
          cursor: 'opaque+/=',
          status: 'failed',
          pipeline: 'ai',
        )).items,
        isEmpty,
      );
    },
  );

  for (final url in [
    'javascript:alert(1)',
    'https://user:token@example.com',
    'https://example.com?token=secret',
    'https://example.com#secret',
    'https://example.com?',
    'https://example.com:0',
  ]) {
    test('unsafe dashboard configuration is rejected: $url', () async {
      respond = (request) async => request.response.write(
        jsonEncode({...configuration, 'dashboardUrl': url}),
      );
      await expectLater(
        repository.getSystemConfiguration(),
        throwsA(
          isA<DocumentProcessingFailure>().having(
            (value) => value.kind,
            'kind',
            DocumentProcessingFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }
}
