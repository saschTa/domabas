import 'package:domabas_api/api.dart' as api;

import '../../../domain/chat/models/chat.dart';

ChatConfiguration chatConfigurationMapper(api.ChatConfiguration value) =>
    ChatConfiguration(
      enabled: value.enabled,
      thinkingEnabled: value.thinkingEnabled,
      provider: value.provider.toString(),
      model: value.model,
      revision: value.revision,
      baseUrl: value.baseUrl,
      hasApiKey: value.hasApiKey,
      contextLength: value.contextLength,
    );
ChatModelContext chatModelContextMapper(
  api.OllamaModelContext value,
  String model,
) {
  if (value.model != model || value.maxContextLength < 1) {
    throw const FormatException('Invalid model context');
  }
  return ChatModelContext(
    model: value.model,
    maxContextLength: value.maxContextLength,
  );
}

ChatConfiguration chatSummaryMapper(api.ChatConfigurationSummary value) =>
    ChatConfiguration(
      enabled: value.enabled,
      provider: value.provider.toString(),
      model: value.model,
      revision: value.revision,
    );
ChatConversation chatConversationMapper(api.ChatConversation value) =>
    ChatConversation(
      id: value.id,
      title: value.title,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      activeTurnId: value.activeTurnId,
    );
ChatMessage chatMessageMapper(api.ChatMessage value) => ChatMessage(
  id: value.id,
  conversationId: value.conversationId,
  sequence: value.sequence,
  role: value.role.toString(),
  content: value.content,
  createdAt: value.createdAt,
  updatedAt: value.updatedAt,
  turnId: value.turnId,
  status: value.status.toString(),
  stage: value.stage.toString(),
  failureCode: value.failureCode,
  provider: value.provider.toString(),
  model: value.model,
  sources: value.sources.map(
    (source) => ChatSource(
      documentId: source.documentId,
      title: source.title,
      excerpt: source.excerpt,
    ),
  ),
);
