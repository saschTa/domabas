final class ChatConfiguration {
  const ChatConfiguration({
    required this.enabled,
    required this.provider,
    required this.model,
    required this.revision,
    this.baseUrl = '',
    this.hasApiKey = false,
    this.contextLength = 32768,
    this.thinkingEnabled = false,
  });
  final bool enabled, hasApiKey, thinkingEnabled;
  final String provider, model, baseUrl;
  final int revision, contextLength;
}

final class ChatModelContext {
  const ChatModelContext({required this.model, required this.maxContextLength});
  final String model;
  final int maxContextLength;
}

final class ChatConfigurationDraft {
  const ChatConfigurationDraft({
    this.enabled = true,
    this.thinkingEnabled = false,
    this.provider = 'ollama',
    this.model = 'qwen3.5:4b',
    this.baseUrl = '',
    this.apiKey = '',
    this.clearApiKey = false,
    this.contextLength = '32768',
  });
  factory ChatConfigurationDraft.saved(ChatConfiguration configuration) =>
      ChatConfigurationDraft(
        enabled: configuration.enabled,
        thinkingEnabled: configuration.thinkingEnabled,
        provider: configuration.provider,
        model: configuration.model,
        baseUrl: configuration.baseUrl,
        contextLength: configuration.contextLength.toString(),
      );
  final bool enabled, thinkingEnabled, clearApiKey;
  final String provider, model, baseUrl, apiKey, contextLength;
  ChatConfigurationDraft copyWith({
    bool? enabled,
    bool? thinkingEnabled,
    String? provider,
    String? model,
    String? baseUrl,
    String? apiKey,
    bool? clearApiKey,
    String? contextLength,
  }) => ChatConfigurationDraft(
    enabled: enabled ?? this.enabled,
    thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
    provider: provider ?? this.provider,
    model: model ?? this.model,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    clearApiKey: clearApiKey ?? this.clearApiKey,
    contextLength: contextLength ?? this.contextLength,
  );
  bool changed(ChatConfiguration saved) =>
      enabled != saved.enabled ||
      thinkingEnabled != saved.thinkingEnabled ||
      provider != saved.provider ||
      model.trim() != saved.model ||
      (contextLengthValue != null
          ? contextLengthValue != saved.contextLength
          : provider == 'ollama') ||
      (provider == 'openai' ? baseUrl.trim() : '') != saved.baseUrl ||
      apiKey.isNotEmpty ||
      clearApiKey;
  String? get error {
    if (provider == 'ollama' && contextLengthError != null) {
      return contextLengthError;
    }
    if (model.trim().isEmpty || model.length > 200) {
      return 'Enter a model name of 1–200 characters.';
    }
    if (provider == 'openai') {
      final uri = Uri.tryParse(baseUrl.trim());
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        return 'Enter an HTTP or HTTPS API base URL without credentials, query or fragment.';
      }
    }
    if (baseUrl.length > 2048) return 'The API base URL is too long.';
    if (apiKey.length > 4096) return 'The API key is too long.';
    return null;
  }

  int? get contextLengthValue {
    final value = int.tryParse(contextLength.trim());
    return value != null && value >= 1024 && value <= 1048576 ? value : null;
  }

  String? get contextLengthError => contextLengthValue == null
      ? 'Enter a whole number from 1,024 to 1,048,576 tokens.'
      : null;
}

final class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.activeTurnId,
  });
  final String id, title;
  final String? activeTurnId;
  final DateTime createdAt, updatedAt;
}

final class ChatSource {
  const ChatSource({
    required this.documentId,
    required this.title,
    this.excerpt = '',
  });
  final String documentId, title, excerpt;
}

final class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.sequence,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.turnId,
    this.status = 'completed',
    this.stage = 'completed',
    this.failureCode,
    this.provider = '',
    this.model = '',
    Iterable<ChatSource> sources = const [],
  }) : sources = List.unmodifiable(sources);
  final String id,
      conversationId,
      role,
      content,
      status,
      stage,
      provider,
      model;
  final int sequence;
  final DateTime createdAt, updatedAt;
  final String? turnId, failureCode;
  final List<ChatSource> sources;
  bool get active =>
      role == 'assistant' && (status == 'queued' || status == 'running');
  String get statusLabel => switch (status) {
    'completed' => 'Answer ready',
    'failed' => 'Reply interrupted',
    'cancelled' => 'Reply stopped',
    _ => switch (stage) {
      'queued' => 'Queued',
      'waiting_for_ingestion' => 'Waiting to start',
      'preparing' => 'Preparing your reply',
      'generating' => 'Thinking',
      'searching_documents' => 'Searching your library',
      'reading_document' => 'Reading documents',
      _ => 'Working on your reply',
    },
  };
  String get statusDescription => switch (status) {
    'failed' => switch (failureCode) {
      'output_limit' =>
        'The model reached its output limit before finishing the reply.',
      'empty_response' => 'The model finished without a final answer.',
      'tool_limit' => 'The assistant reached its document lookup limit. Try a more specific question.',
      'timeout' =>
        'This reply took too long. You can send your question again.',
      'permission_denied' ||
      'forbidden' ||
      'access_revoked' => 'Your access changed before this reply could finish.',
      _ => 'The assistant could not finish this reply. You can send your question again.',
    },
    'cancelled' => 'Your messages are kept. You can send this question again.',
    _ => switch (stage) {
      'waiting_for_ingestion' => 'Your message is saved and will continue automatically when it can start.',
      'queued' => 'Your message is saved and waiting to start.',
      'searching_documents' => 'Looking for relevant documents you can access.',
      'reading_document' => 'Reading retrieved text to prepare your answer.',
      _ => 'The assistant is working on your request.',
    },
  };
}

final class ChatPage<T> {
  ChatPage({required Iterable<T> items, this.nextCursor})
    : items = List.unmodifiable(items);
  final List<T> items;
  final String? nextCursor;
}

final class ChatModelPage {
  ChatModelPage({required Iterable<String> items, this.nextOffset})
    : items = List.unmodifiable(items);
  final List<String> items;
  final int? nextOffset;
}

final class ChatAcceptedMessage {
  const ChatAcceptedMessage({
    required this.userMessage,
    required this.assistantMessage,
  });
  final ChatMessage userMessage, assistantMessage;
}

final class ChatFailure implements Exception {
  const ChatFailure(this.code);
  final String code;
  String get message => switch (code) {
    'invalid_request' => 'Check your entries and try again.',
    'unauthorized' => 'Please sign in again.',
    'forbidden' => 'You do not have permission to use this feature.',
    'not_found' => 'This conversation is no longer available.',
    'conflict' => 'The saved state changed. Refresh to see the latest version.',
    'limited' =>
      'There are too many pending replies. Please try again shortly.',
    'cancelled' => 'The request was cancelled.',
    _ => 'Chat could not reach the server. Please try again.',
  };
}
