import 'dart:async';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/chat/interfaces/chat_repository.dart';
import '../../../domain/chat/models/chat.dart';
import '../datasources/chat_remote_data_source.dart';
import 'chat_mapper.dart';

final class RemoteChatRepository implements ChatRepository {
  RemoteChatRepository(this._source);
  final ChatRemoteDataSource _source;
  @override
  void cancelRequests() => _source.cancelRequests();
  @override
  Future<ChatConfiguration> configuration({
    bool admin = false,
    Future<void>? cancel,
  }) => _translate(
    () async => admin
        ? chatConfigurationMapper(await _source.adminConfiguration(cancel))
        : chatSummaryMapper(await _source.configuration(cancel)),
  );
  @override
  Future<ChatConfiguration> updateConfiguration(
    ChatConfigurationDraft draft, {
    required int expectedRevision,
    Future<void>? cancel,
  }) => _translate(
    () async => chatConfigurationMapper(
      await _source.updateConfiguration(
        api.UpdateChatConfigurationRequest(
          expectedRevision: expectedRevision,
          enabled: draft.enabled,
          thinkingEnabled: draft.thinkingEnabled,
          provider: draft.provider == 'openai'
              ? api.UpdateChatConfigurationRequestProviderEnum.openai
              : api.UpdateChatConfigurationRequestProviderEnum.ollama,
          model: draft.model.trim(),
          contextLength: draft.contextLengthValue,
          baseUrl: draft.provider == 'openai' ? draft.baseUrl.trim() : '',
          apiKey: draft.apiKey.isEmpty || draft.clearApiKey
              ? null
              : draft.apiKey,
          clearApiKey: draft.clearApiKey ? true : null,
        ),
        cancel,
      ),
    ),
  );
  @override
  Future<ChatModelContext> modelContext(String model, {Future<void>? cancel}) =>
      _translate(
        () async => chatModelContextMapper(
          await _source.modelContext(model, cancel),
          model,
        ),
      );
  @override
  Future<ChatModelPage> models({int offset = 0, Future<void>? cancel}) =>
      _translate(() async {
        final page = await _source.models(offset, cancel);
        return ChatModelPage(
          items: page.items.map((model) => model.name),
          nextOffset: page.nextOffset,
        );
      });
  @override
  Future<ChatPage<ChatConversation>> conversations({
    String? cursor,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.conversations(cursor, cancel);
    return ChatPage(
      items: page.items.map(chatConversationMapper),
      nextCursor: page.nextCursor,
    );
  });
  @override
  Future<ChatConversation> createConversation(
    String requestId, {
    Future<void>? cancel,
  }) => _translate(
    () async => chatConversationMapper(await _source.create(requestId, cancel)),
  );
  @override
  Future<ChatConversation> conversation(String id, {Future<void>? cancel}) =>
      _translate(
        () async =>
            chatConversationMapper(await _source.conversation(id, cancel)),
      );
  @override
  Future<void> deleteConversation(String id, {Future<void>? cancel}) =>
      _translate(() => _source.delete(id, cancel));
  @override
  Future<ChatPage<ChatMessage>> messages(
    String conversationId, {
    String? cursor,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.messages(conversationId, cursor, cancel);
    return ChatPage(
      items: page.items.map(chatMessageMapper),
      nextCursor: page.nextCursor,
    );
  });
  @override
  Future<ChatAcceptedMessage> send(
    String conversationId, {
    required String requestId,
    required String content,
    Future<void>? cancel,
  }) => _translate(() async {
    final accepted = await _source.send(
      conversationId,
      requestId,
      content,
      cancel,
    );
    return ChatAcceptedMessage(
      userMessage: chatMessageMapper(accepted.userMessage),
      assistantMessage: chatMessageMapper(accepted.assistantMessage),
    );
  });
  @override
  Future<ChatMessage> cancelTurn(
    String conversationId,
    String turnId, {
    Future<void>? cancel,
  }) => _translate(
    () async => chatMessageMapper(
      await _source.cancelTurn(conversationId, turnId, cancel),
    ),
  );
  Future<T> _translate<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on api.ApiException catch (error) {
      throw ChatFailure(switch (error.code) {
        400 || 422 => 'invalid_request',
        401 => 'unauthorized',
        403 => 'forbidden',
        404 => 'not_found',
        409 => 'conflict',
        429 => 'limited',
        499 => 'cancelled',
        _ => 'unavailable',
      });
    } on FormatException {
      throw const ChatFailure('unavailable');
    } on TimeoutException {
      throw const ChatFailure('unavailable');
    } on http.ClientException {
      throw const ChatFailure('unavailable');
    }
  }
}
