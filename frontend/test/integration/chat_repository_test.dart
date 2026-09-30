import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/chat/datasources/chat_remote_data_source.dart';
import 'package:domabas/data/chat/repos/remote_chat_repository.dart';
import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late api.ApiClient client;
  late RemoteChatRepository repository;
  late Future<void> Function(HttpRequest) respond;
  final config = {
    'enabled': true,
    'provider': 'openai',
    'model': 'chat-model',
    'baseUrl': 'https://example.com/v1',
    'hasApiKey': true,
    'contextLength': 32768,
    'revision': 3,
  };
  final conversation = {
    'id': 'conversation',
    'title': 'A question',
    'createdAt': '2026-09-22T10:00:00Z',
    'updatedAt': '2026-09-22T10:00:00Z',
  };
  final message = {
    'id': 'message',
    'conversationId': 'conversation',
    'sequence': 2,
    'role': 'assistant',
    'content': 'Your answer',
    'turnId': 'turn',
    'status': 'completed',
    'stage': 'completed',
    'provider': 'openai',
    'model': 'chat-model',
    'createdAt': '2026-09-22T10:00:00Z',
    'updatedAt': '2026-09-22T10:00:00Z',
    'sources': [
      {'documentId': 'document', 'title': 'Invoice', 'excerpt': '119 EUR'},
    ],
  };
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}');
    repository = RemoteChatRepository(
      ChatRemoteDataSource(api.ChatApi(client)),
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

  test('maps public/admin configuration and explicitly retains, replaces or removes keys', () async {
    final requests = <({String path, Map<String, dynamic>? body})>[];
    respond = (request) async {
      final raw = await utf8.decoder.bind(request).join();
      requests.add((
        path: request.uri.path,
        body: raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>,
      ));
      request.response.write(jsonEncode(config));
    };
    expect((await repository.configuration()).model, 'chat-model');
    expect((await repository.configuration(admin: true)).hasApiKey, isTrue);
    for (final draft in [
      const ChatConfigurationDraft(
        provider: 'openai',
        model: 'new',
        baseUrl: 'https://example.com/v1',
      ),
      const ChatConfigurationDraft(
        provider: 'openai',
        model: 'new',
        baseUrl: 'https://example.com/v1',
        apiKey: 'replacement',
      ),
      const ChatConfigurationDraft(
        provider: 'openai',
        model: 'new',
        baseUrl: 'https://example.com/v1',
        clearApiKey: true,
      ),
    ]) {
      await repository.updateConfiguration(draft, expectedRevision: 3);
    }
    expect(requests.first.path, '/api/v1/chat/configuration');
    expect(requests[1].path, '/api/v1/system/chat/configuration');
    expect(requests[2].body!['expectedRevision'], 3);
    expect(requests[2].body!['contextLength'], 32768);
    expect(requests[2].body!['apiKey'], isNull);
    expect(requests[3].body!['apiKey'], 'replacement');
    expect(requests[4].body!['clearApiKey'], isTrue);
    expect(requests[4].body!['apiKey'], isNull);
  });

  test('chat thinking maps older reads to off and sends explicit on and off values', () async {
    respond = (request) async => request.response.write(jsonEncode(config));
    expect(
      (await repository.configuration(admin: true)).thinkingEnabled,
      isFalse,
    );
    for (final enabled in [true, false]) {
      respond = (request) async {
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        expect(body['thinkingEnabled'], enabled);
        request.response.write(
          jsonEncode({...config, 'thinkingEnabled': enabled}),
        );
      };
      final saved = await repository.updateConfiguration(
        ChatConfigurationDraft(thinkingEnabled: enabled),
        expectedRevision: 3,
      );
      expect(saved.thinkingEnabled, enabled);
    }
  });

  test('maps paginated history, messages, trusted source records and bounded model pages', () async {
    final paths = <Uri>[];
    respond = (request) async {
      paths.add(request.uri);
      request.response.write(
        jsonEncode(
          request.uri.path.endsWith('/models')
              ? {
                  'items': [
                    {'name': 'qwen3.5:4b'},
                  ],
                  'nextOffset': 40,
                }
              : request.uri.path.endsWith('/messages')
              ? {
                  'items': [message],
                  'nextCursor': 'earlier',
                }
              : {
                  'items': [conversation],
                  'nextCursor': 'older',
                },
        ),
      );
    };
    expect(
      (await repository.conversations(cursor: 'older')).nextCursor,
      'older',
    );
    final page = await repository.messages('conversation', cursor: 'earlier');
    expect(page.items.single.sources.single.documentId, 'document');
    expect(page.items.single.statusLabel, 'Answer ready');
    expect(page.nextCursor, 'earlier');
    final models = await repository.models(offset: 20);
    expect(models.items.single, 'qwen3.5:4b');
    expect(models.nextOffset, 40);
    expect(paths[0].queryParameters, {'limit': '20', 'cursor': 'older'});
    expect(paths[2].queryParameters, {'limit': '20', 'offset': '20'});
  });

  test('acceptance sends stable caller request IDs and cancel returns persisted status', () async {
    final bodies = <Map<String, dynamic>>[];
    respond = (request) async {
      final raw = await utf8.decoder.bind(request).join();
      if (raw.isNotEmpty) bodies.add(jsonDecode(raw) as Map<String, dynamic>);
      request.response.write(
        jsonEncode(
          request.uri.path.endsWith('/cancel')
              ? {...message, 'status': 'cancelled', 'stage': 'cancelled'}
              : request.uri.path.endsWith('/messages')
              ? {
                  'userMessage': {
                    ...message,
                    'id': 'user',
                    'role': 'user',
                    'content': 'Question',
                  },
                  'assistantMessage': message,
                }
              : conversation,
        ),
      );
    };
    await repository.createConversation('create-id');
    final accepted = await repository.send(
      'conversation',
      requestId: 'send-id',
      content: 'Question',
    );
    expect(accepted.userMessage.content, 'Question');
    expect(accepted.assistantMessage.sources.single.title, 'Invoice');
    expect(bodies, [
      {'requestId': 'create-id'},
      {'requestId': 'send-id', 'content': 'Question'},
    ]);
    expect(
      (await repository.cancelTurn('conversation', 'turn')).status,
      'cancelled',
    );
  });

  for (final entry in {
    400: 'invalid_request',
    403: 'forbidden',
    404: 'not_found',
    409: 'conflict',
    429: 'limited',
    503: 'unavailable',
  }.entries) {
    test('sanitizes ${entry.key} responses', () async {
      respond = (request) async {
        request.response.statusCode = entry.key;
        request.response.write('{"message":"secret private provider output"}');
      };
      await expectLater(
        repository.configuration(),
        throwsA(
          isA<ChatFailure>()
              .having((failure) => failure.code, 'code', entry.value)
              .having(
                (failure) => failure.message.contains('secret'),
                'secret excluded',
                isFalse,
              ),
        ),
      );
    });
  }
  test('malformed model response becomes safe domain failure', () async {
    respond = (request) async => request.response.write('{"enabled":true}');
    await expectLater(repository.configuration(), throwsA(isA<ChatFailure>()));
  });
  test(
    'model context maps bounded metadata and preserves slash model query',
    () async {
      const model = 'publisher/model:latest';
      respond = (request) async {
        expect(request.uri.path, '/api/v1/system/chat/model-context');
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
          throwsA(isA<ChatFailure>()),
        );
      }
    },
  );
  test('configuration preserves requested context and omits invalid external draft', () async {
    final bodies = <Map<String, dynamic>>[];
    respond = (request) async {
      bodies.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response.write(jsonEncode({...config, 'contextLength': 65536}));
    };
    final saved = await repository.updateConfiguration(
      const ChatConfigurationDraft(contextLength: '65536'),
      expectedRevision: 3,
    );
    expect(saved.contextLength, 65536);
    expect(bodies.single['contextLength'], 65536);
    await repository.updateConfiguration(
      const ChatConfigurationDraft(
        provider: 'openai',
        baseUrl: 'https://example.com/v1',
        contextLength: '',
      ),
      expectedRevision: 3,
    );
    expect(bodies.last['contextLength'], isNull);
  });
}
