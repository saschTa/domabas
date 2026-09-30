import 'dart:async';

import 'package:domabas/domain/chat/interfaces/chat_repository.dart';
import 'package:domabas/domain/chat/models/chat.dart';

final class FakeChatRepository implements ChatRepository {
  ChatConfiguration saved = const ChatConfiguration(
    enabled: true,
    provider: 'ollama',
    model: 'qwen3.5:4b',
    revision: 1,
  );
  List<ChatConversation> history = [];
  Map<String, List<ChatMessage>> transcript = {};
  ChatFailure? sendFailure,
      saveFailure,
      modelFailure,
      deleteFailure,
      historyFailure;
  Completer<ChatPage<ChatMessage>>? delayedMessages;
  Completer<ChatPage<ChatConversation>>? delayedHistory;
  Completer<void>? delayedDelete;
  Completer<ChatConfiguration>? delayedSave;
  final createRequests = <String>[];
  final sendRequests = <({String id, String requestId, String content})>[];
  final messageCursors = <String?>[];
  final historyCursors = <String?>[];
  final deleteRequests = <String>[];
  int readCount = 0, saveCount = 0, cancelCount = 0;
  ChatConfigurationDraft? lastDraft;
  Future<ChatModelContext> Function(String)? onModelContext;
  @override
  Future<ChatModelContext> modelContext(
    String model, {
    Future<void>? cancel,
  }) async => onModelContext != null
      ? onModelContext!(model)
      : ChatModelContext(model: model, maxContextLength: 131072);
  bool cancelled = false;
  @override
  void cancelRequests() => cancelled = true;
  @override
  Future<ChatConfiguration> configuration({
    bool admin = false,
    Future<void>? cancel,
  }) async => saved;
  @override
  Future<ChatConfiguration> updateConfiguration(
    ChatConfigurationDraft draft, {
    required int expectedRevision,
    Future<void>? cancel,
  }) async {
    saveCount++;
    lastDraft = draft;
    if (saveFailure != null) throw saveFailure!;
    if (delayedSave != null) return delayedSave!.future;
    return saved = ChatConfiguration(
      enabled: draft.enabled,
      thinkingEnabled: draft.thinkingEnabled,
      provider: draft.provider,
      model: draft.model,
      baseUrl: draft.baseUrl,
      hasApiKey:
          !draft.clearApiKey && (draft.apiKey.isNotEmpty || saved.hasApiKey),
      revision: expectedRevision + 1,
      contextLength: draft.contextLengthValue ?? saved.contextLength,
    );
  }

  @override
  Future<ChatModelPage> models({int offset = 0, Future<void>? cancel}) async {
    if (modelFailure != null) throw modelFailure!;
    return ChatModelPage(
      items: offset == 0 ? ['qwen3.5:4b'] : ['qwen3:8b'],
      nextOffset: offset == 0 ? 20 : null,
    );
  }

  @override
  Future<ChatPage<ChatConversation>> conversations({
    String? cursor,
    Future<void>? cancel,
  }) async {
    historyCursors.add(cursor);
    final delayed = delayedHistory;
    if (delayed != null) {
      delayedHistory = null;
      return delayed.future;
    }
    if (historyFailure != null) throw historyFailure!;
    final offset = cursor == null ? 0 : int.parse(cursor);
    return ChatPage(
      items: history.skip(offset).take(20),
      nextCursor: history.length > offset + 20 ? '${offset + 20}' : null,
    );
  }

  @override
  Future<ChatConversation> createConversation(
    String requestId, {
    Future<void>? cancel,
  }) async {
    createRequests.add(requestId);
    if (history.isEmpty) history.add(chatConversation('created'));
    return history.first;
  }

  @override
  Future<ChatConversation> conversation(
    String id, {
    Future<void>? cancel,
  }) async => history.firstWhere((item) => item.id == id);
  @override
  Future<void> deleteConversation(String id, {Future<void>? cancel}) async {
    deleteRequests.add(id);
    if (delayedDelete != null) await delayedDelete!.future;
    if (deleteFailure != null) throw deleteFailure!;
    history.removeWhere((item) => item.id == id);
  }

  @override
  Future<ChatPage<ChatMessage>> messages(
    String conversationId, {
    String? cursor,
    Future<void>? cancel,
  }) async {
    readCount++;
    messageCursors.add(cursor);
    final delayed = delayedMessages;
    if (delayed != null) {
      delayedMessages = null;
      return delayed.future;
    }
    final items = (transcript[conversationId] ?? []).reversed.toList();
    final offset = cursor == null ? 0 : int.parse(cursor);
    return ChatPage(
      items: items.skip(offset).take(20),
      nextCursor: items.length > offset + 20 ? '${offset + 20}' : null,
    );
  }

  @override
  Future<ChatAcceptedMessage> send(
    String conversationId, {
    required String requestId,
    required String content,
    Future<void>? cancel,
  }) async {
    sendRequests.add((
      id: conversationId,
      requestId: requestId,
      content: content,
    ));
    if (sendFailure != null) throw sendFailure!;
    final items = transcript.putIfAbsent(conversationId, () => []);
    final user = chatMessage(
      'user-${items.length}',
      conversationId: conversationId,
      role: 'user',
      content: content,
      sequence: items.length + 1,
    );
    final assistant = chatMessage(
      'assistant-${items.length}',
      conversationId: conversationId,
      sequence: items.length + 2,
      status: 'queued',
      stage: 'queued',
    );
    items.addAll([user, assistant]);
    return ChatAcceptedMessage(userMessage: user, assistantMessage: assistant);
  }

  @override
  Future<ChatMessage> cancelTurn(
    String conversationId,
    String turnId, {
    Future<void>? cancel,
  }) async {
    cancelCount++;
    final items = transcript[conversationId]!;
    final old = items.last;
    final result = chatMessage(
      old.id,
      conversationId: conversationId,
      sequence: old.sequence,
      status: 'cancelled',
      stage: 'cancelled',
    );
    items[items.length - 1] = result;
    return result;
  }
}

ChatConversation chatConversation(String id, {DateTime? createdAt}) =>
    ChatConversation(
      id: id,
      title: 'Conversation $id',
      createdAt: createdAt ?? DateTime.utc(2026, 9, 22),
      updatedAt: DateTime.utc(2026, 9, 22),
    );
ChatMessage chatMessage(
  String id, {
  String conversationId = 'one',
  int sequence = 1,
  String role = 'assistant',
  String content = '',
  String status = 'completed',
  String stage = 'completed',
  Iterable<ChatSource> sources = const [],
}) => ChatMessage(
  id: id,
  conversationId: conversationId,
  sequence: sequence,
  role: role,
  content: content,
  status: status,
  stage: stage,
  turnId: 'turn-$id',
  createdAt: DateTime.utc(2026, 9, 22),
  updatedAt: DateTime.utc(2026, 9, 22),
  sources: sources,
);
