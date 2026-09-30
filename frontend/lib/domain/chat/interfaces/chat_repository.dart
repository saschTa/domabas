import '../models/chat.dart';

abstract interface class ChatRepository {
  Future<ChatConfiguration> configuration({
    bool admin = false,
    Future<void>? cancel,
  });
  Future<ChatConfiguration> updateConfiguration(
    ChatConfigurationDraft draft, {
    required int expectedRevision,
    Future<void>? cancel,
  });
  Future<ChatModelPage> models({int offset = 0, Future<void>? cancel});
  Future<ChatModelContext> modelContext(String model, {Future<void>? cancel});
  Future<ChatPage<ChatConversation>> conversations({
    String? cursor,
    Future<void>? cancel,
  });
  Future<ChatConversation> createConversation(
    String requestId, {
    Future<void>? cancel,
  });
  Future<ChatConversation> conversation(String id, {Future<void>? cancel});
  Future<void> deleteConversation(String id, {Future<void>? cancel});
  Future<ChatPage<ChatMessage>> messages(
    String conversationId, {
    String? cursor,
    Future<void>? cancel,
  });
  Future<ChatAcceptedMessage> send(
    String conversationId, {
    required String requestId,
    required String content,
    Future<void>? cancel,
  });
  Future<ChatMessage> cancelTurn(
    String conversationId,
    String turnId, {
    Future<void>? cancel,
  });
  void cancelRequests();
}
