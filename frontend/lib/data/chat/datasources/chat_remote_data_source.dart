import 'dart:async';

import 'package:domabas_api/api.dart' as api;

final class ChatRemoteDataSource {
  ChatRemoteDataSource(this._api, {this.timeout = const Duration(seconds: 20)});
  final api.ChatApi _api;
  final Duration timeout;
  final _requests = <Completer<void>>{};
  bool _cancelled = false;
  void cancelRequests() {
    _cancelled = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<api.ChatConfigurationSummary> configuration(Future<void>? cancel) =>
      _request(
        (abort) => _api.getChatConfiguration(abortTrigger: abort),
        cancel,
      );
  Future<api.ChatConfiguration> adminConfiguration(Future<void>? cancel) =>
      _request(
        (abort) => _api.getChatAdminConfiguration(abortTrigger: abort),
        cancel,
      );
  Future<api.ChatConfiguration> updateConfiguration(
    api.UpdateChatConfigurationRequest body,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.updateChatConfiguration(body, abortTrigger: abort),
    cancel,
  );
  Future<api.ChatModelPage> models(int offset, Future<void>? cancel) =>
      _request(
        (abort) =>
            _api.listChatModels(limit: 20, offset: offset, abortTrigger: abort),
        cancel,
      );
  Future<api.OllamaModelContext> modelContext(
    String model,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.getChatModelContext(model, abortTrigger: abort),
    cancel,
  );
  Future<api.ChatConversationPage> conversations(
    String? cursor,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.listChatConversations(
      limit: 20,
      cursor: cursor,
      abortTrigger: abort,
    ),
    cancel,
  );
  Future<api.ChatConversation> create(String requestId, Future<void>? cancel) =>
      _request(
        (abort) => _api.createChatConversation(
          api.CreateChatConversationRequest(requestId: requestId),
          abortTrigger: abort,
        ),
        cancel,
      );
  Future<api.ChatConversation> conversation(String id, Future<void>? cancel) =>
      _request(
        (abort) => _api.getChatConversation(id, abortTrigger: abort),
        cancel,
      );
  Future<void> delete(String id, Future<void>? cancel) async {
    await _request((abort) async {
      await _api.deleteChatConversation(id, abortTrigger: abort);
      return true;
    }, cancel);
  }

  Future<api.ChatMessagePage> messages(
    String id,
    String? cursor,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.listChatMessages(
      id,
      limit: 20,
      cursor: cursor,
      abortTrigger: abort,
    ),
    cancel,
  );
  Future<api.ChatAcceptedTurn> send(
    String id,
    String requestId,
    String content,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.sendChatMessage(
      id,
      api.SendChatMessageRequest(requestId: requestId, content: content),
      abortTrigger: abort,
    ),
    cancel,
  );
  Future<api.ChatMessage> cancelTurn(
    String id,
    String turnId,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.cancelChatTurn(id, turnId, abortTrigger: abort),
    cancel,
  );
  Future<T> _request<T>(
    Future<T?> Function(Future<void>) send,
    Future<void>? cancel,
  ) async {
    if (_cancelled) throw api.ApiException(499, 'Cancelled');
    final abort = Completer<void>();
    _requests.add(abort);
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      stop();
    });
    if (cancel != null) unawaited(cancel.then((_) => stop()));
    try {
      final result = await send(abort.future).timeout(timeout);
      if (timedOut) throw TimeoutException('Chat request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      if (result == null) throw const FormatException('Missing chat response');
      return result;
    } on TypeError {
      throw const FormatException('Invalid chat response');
    } on AssertionError {
      throw const FormatException('Missing chat fields');
    } catch (_) {
      if (timedOut) throw TimeoutException('Chat request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      rethrow;
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}
