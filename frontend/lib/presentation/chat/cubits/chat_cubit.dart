import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';
import '../../../domain/chat/interfaces/chat_repository.dart';
import '../../../domain/chat/models/chat.dart';

final class ChatState {
  ChatState({
    this.configuration,
    Iterable<ChatConversation> conversations = const [],
    Iterable<ChatMessage> messages = const [],
    this.selected,
    this.conversationCursor,
    this.messageCursor,
    this.draft = '',
    this.loading = false,
    this.loadingMessages = false,
    this.loadingHistory = false,
    this.sending = false,
    this.stopping = false,
    this.uncertain = false,
    this.loaded = false,
    this.error,
    this.updatesError,
    this.deletingConversationId,
    this.deleteError,
  }) : conversations = List.unmodifiable(conversations),
       messages = List.unmodifiable(messages);
  final ChatConfiguration? configuration;
  final List<ChatConversation> conversations;
  final List<ChatMessage> messages;
  final ChatConversation? selected;
  final String? conversationCursor, messageCursor, error, updatesError;
  final String draft;
  final String? deletingConversationId, deleteError;
  final bool loading,
      loadingMessages,
      loadingHistory,
      sending,
      stopping,
      uncertain,
      loaded;
  ChatMessage? get activeMessage =>
      messages.where((message) => message.active).lastOrNull;
  bool get hasActiveTurn =>
      activeMessage != null || selected?.activeTurnId != null;
  bool get canManageConversations =>
      !sending && !stopping && !uncertain && deletingConversationId == null;
  String? get draftError =>
      draft.runes.length > 8000 ? 'Use no more than 8,000 characters.' : null;
  bool get canSend =>
      configuration?.enabled == true &&
      draft.trim().isNotEmpty &&
      draftError == null &&
      !sending &&
      deletingConversationId == null &&
      !loadingMessages &&
      !hasActiveTurn &&
      !uncertain;
}

final class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._repository, {required bool allowed})
    : allowed = allowed && _repository != null,
      super(ChatState());
  final ChatRepository? _repository;
  final bool allowed;
  final _drafts = <String, String>{};
  final _conversationPageIds = <String>{};
  final _messagePageIds = <String>{};
  Completer<void>? _selectionCancel;
  int _selectionEpoch = 0, _historyEpoch = 0;
  bool _active = false, _refreshing = false;
  String? _pendingRequestId,
      _pendingCreateId,
      _pendingContent,
      _pendingConversationId;

  void setActive(bool active) {
    if (isClosed || !allowed || _active == active) return;
    _active = active;
    _refresh.setActive(active);
    if (active) {
      unawaited(load());
    }
  }

  late final _refresh = AutomaticRefresh(
    read: () => load(automatic: true),
    busy: () =>
        _refreshing ||
        state.loading ||
        state.loadingMessages ||
        state.loadingHistory ||
        state.sending ||
        state.stopping ||
        state.deletingConversationId != null,
  );
  void invalidate() => _refresh.invalidate();

  void editDraft(String value) {
    if (isClosed ||
        !allowed ||
        state.sending ||
        state.uncertain ||
        state.deletingConversationId != null) {
      return;
    }
    emit(_state(draft: value));
  }

  Future<void> load({bool more = false, bool automatic = false}) async {
    if (isClosed ||
        !allowed ||
        !_active ||
        state.loading ||
        state.loadingHistory ||
        state.sending ||
        state.deletingConversationId != null ||
        (more && state.conversationCursor == null)) {
      return;
    }
    final epoch = ++_historyEpoch;
    emit(_state(loading: !more && !automatic, loadingHistory: more));
    try {
      final page = await _repository!.conversations(
        cursor: more ? state.conversationCursor : null,
      );
      final configuration = more
          ? state.configuration
          : await _repository.configuration();
      if (isClosed || epoch != _historyEpoch) return;
      final conversations = _mergeConversations(
        state.conversations,
        page.items,
      );
      final conversationCursor =
          more ||
              !state.loaded ||
              (page.nextCursor != null &&
                  !page.items.any(
                    (item) => _conversationPageIds.contains(item.id),
                  ))
          ? page.nextCursor
          : state.conversationCursor;
      _conversationPageIds.addAll(page.items.map((item) => item.id));
      emit(
        _state(
          loading: false,
          loadingHistory: false,
          configuration: configuration,
          conversations: conversations,
          conversationCursor: conversationCursor,
          loaded: true,
        ),
      );
      if (state.selected != null) await refreshMessages();
    } on ChatFailure catch (failure) {
      if (!isClosed && epoch == _historyEpoch) {
        emit(
          _state(loading: false, loadingHistory: false, error: failure.message),
        );
      }
    }
  }

  void newConversation() {
    if (isClosed ||
        state.sending ||
        state.stopping ||
        state.uncertain ||
        state.deletingConversationId != null) {
      return;
    }
    _rememberDraft();
    _stopSelection();
    _messagePageIds.clear();
    emit(
      ChatState(
        configuration: state.configuration,
        conversations: state.conversations,
        conversationCursor: state.conversationCursor,
        loaded: state.loaded,
        draft: _drafts[''] ?? '',
      ),
    );
  }

  Future<void> select(ChatConversation conversation) async {
    if (isClosed ||
        state.sending ||
        state.stopping ||
        state.uncertain ||
        state.deletingConversationId != null ||
        conversation.id == state.selected?.id) {
      return;
    }
    _rememberDraft();
    _stopSelection();
    _messagePageIds.clear();
    emit(
      ChatState(
        configuration: state.configuration,
        conversations: state.conversations,
        conversationCursor: state.conversationCursor,
        loaded: state.loaded,
        selected: conversation,
        draft: _drafts[conversation.id] ?? '',
        loadingMessages: true,
      ),
    );
    await _readMessages(initial: true);
  }

  Future<void> earlierMessages() async {
    if (state.messageCursor == null ||
        state.loadingMessages ||
        state.sending ||
        state.deletingConversationId != null) {
      return;
    }
    await _readMessages(more: true);
  }

  Future<void> refreshMessages() async {
    if (!_active ||
        _refreshing ||
        state.loadingMessages ||
        state.sending ||
        state.deletingConversationId != null ||
        state.selected == null) {
      return;
    }
    await _readMessages();
  }

  Future<void> _readMessages({bool initial = false, bool more = false}) async {
    final selected = state.selected;
    if (isClosed || selected == null || _refreshing) return;
    final epoch = _selectionEpoch;
    final cancel = _selectionCancel ??= Completer<void>();
    _refreshing = true;
    if (more) emit(_state(loadingMessages: true));
    try {
      final page = await _repository!.messages(
        selected.id,
        cursor: more ? state.messageCursor : null,
        cancel: cancel.future,
      );
      if (isClosed || epoch != _selectionEpoch) return;
      final conversation = await _repository.conversation(
        selected.id,
        cancel: cancel.future,
      );
      if (isClosed || epoch != _selectionEpoch) return;
      final messageCursor =
          initial ||
              more ||
              (page.nextCursor != null &&
                  !page.items.any((item) => _messagePageIds.contains(item.id)))
          ? page.nextCursor
          : state.messageCursor;
      _messagePageIds.addAll(page.items.map((item) => item.id));
      emit(
        _state(
          loadingMessages: false,
          messages: _mergeMessages(state.messages, page.items),
          selected: conversation,
          conversations: _mergeConversations(state.conversations, [
            conversation,
          ]),
          messageCursor: messageCursor,
        ),
      );
    } on ChatFailure catch (failure) {
      if (!isClosed && epoch == _selectionEpoch) {
        emit(
          _state(
            loadingMessages: false,
            error: initial || more ? failure.message : null,
            updatesError: initial || more
                ? null
                : 'Updates paused. ${failure.message}',
          ),
        );
      }
    } finally {
      if (epoch == _selectionEpoch) _refreshing = false;
    }
  }

  Future<void> send({bool reconcile = false}) async {
    if (isClosed ||
        !allowed ||
        !_active ||
        state.sending ||
        state.deletingConversationId != null ||
        (!reconcile && !state.canSend) ||
        (reconcile && !state.uncertain)) {
      return;
    }
    _stopSelection();
    _historyEpoch++;
    _pendingRequestId ??= _uuid();
    _pendingCreateId ??= _uuid();
    _pendingContent ??= state.draft.trim();
    _pendingConversationId ??= state.selected?.id;
    emit(_state(sending: true, loading: false, loadingHistory: false));
    try {
      if (_pendingConversationId == null) {
        final conversation = await _repository!.createConversation(
          _pendingCreateId!,
        );
        if (isClosed) return;
        _pendingConversationId = conversation.id;
        emit(
          _state(
            selected: conversation,
            conversations: _mergeConversations(state.conversations, [
              conversation,
            ]),
            sending: true,
          ),
        );
      }
      final accepted = await _repository!.send(
        _pendingConversationId!,
        requestId: _pendingRequestId!,
        content: _pendingContent!,
      );
      if (isClosed) return;
      _drafts[state.selected!.id] = '';
      _drafts[''] = '';
      _clearPending();
      emit(
        _state(
          messages: _mergeMessages(state.messages, [
            accepted.userMessage,
            accepted.assistantMessage,
          ]),
          draft: '',
          sending: false,
          uncertain: false,
        ),
      );
      await refreshMessages();
    } on ChatFailure catch (failure) {
      if (isClosed) return;
      final uncertain = ![
        'invalid_request',
        'forbidden',
        'not_found',
        'limited',
      ].contains(failure.code);
      if (!uncertain) _clearPending();
      emit(
        _state(
          sending: false,
          uncertain: uncertain,
          error: uncertain
              ? 'Your message may have been saved. Check its status before sending another message.'
              : failure.message,
        ),
      );
    }
  }

  Future<void> stop() async {
    final turn = state.activeMessage?.turnId ?? state.selected?.activeTurnId;
    if (isClosed ||
        state.stopping ||
        state.deletingConversationId != null ||
        turn == null ||
        state.selected == null) {
      return;
    }
    _stopSelection();
    final epoch = _selectionEpoch;
    emit(_state(stopping: true));
    try {
      final message = await _repository!.cancelTurn(state.selected!.id, turn);
      if (isClosed || epoch != _selectionEpoch) return;
      emit(
        _state(
          stopping: false,
          messages: _mergeMessages(state.messages, [message]),
        ),
      );
      await refreshMessages();
    } on ChatFailure catch (failure) {
      if (!isClosed && epoch == _selectionEpoch) {
        emit(_state(stopping: false, error: failure.message));
      }
    }
  }

  Future<void> deleteConversation(ChatConversation conversation) async {
    if (isClosed ||
        !allowed ||
        !_active ||
        state.sending ||
        state.stopping ||
        state.uncertain ||
        state.deletingConversationId != null ||
        !state.conversations.any((item) => item.id == conversation.id)) {
      return;
    }
    final selected = state.selected?.id == conversation.id;
    _historyEpoch++;
    if (selected) _stopSelection();
    emit(
      _state(
        deletingConversationId: conversation.id,
        deleteError: null,
        loading: false,
        loadingHistory: false,
        loadingMessages: selected ? false : state.loadingMessages,
      ),
    );
    try {
      await _repository!.deleteConversation(conversation.id);
    } on ChatFailure catch (failure) {
      if (isClosed) return;
      if (failure.code != 'not_found') {
        emit(
          _state(
            deletingConversationId: null,
            deleteError:
                'Could not delete the conversation. ${failure.message}',
          ),
        );
        return;
      }
    }
    if (isClosed) return;
    _drafts.remove(conversation.id);
    _conversationPageIds.remove(conversation.id);
    final conversations = state.conversations
        .where((item) => item.id != conversation.id)
        .toList();
    if (selected) {
      _drafts.remove('');
      _messagePageIds.clear();
      emit(
        ChatState(
          configuration: state.configuration,
          conversations: conversations,
          conversationCursor: state.conversationCursor,
          loaded: state.loaded,
        ),
      );
    } else {
      emit(
        _state(
          conversations: conversations,
          deletingConversationId: null,
          deleteError: null,
        ),
      );
    }
  }

  void sendAgain(ChatMessage assistant) {
    if (state.hasActiveTurn || state.sending || state.uncertain) return;
    final prompt = state.messages
        .where(
          (message) =>
              message.role == 'user' && message.sequence < assistant.sequence,
        )
        .lastOrNull;
    if (prompt != null) editDraft(prompt.content);
  }

  ChatState _state({
    ChatConfiguration? configuration,
    List<ChatConversation>? conversations,
    List<ChatMessage>? messages,
    ChatConversation? selected,
    Object? conversationCursor = _unchanged,
    Object? messageCursor = _unchanged,
    String? draft,
    bool? loading,
    bool? loadingHistory,
    bool? loadingMessages,
    bool? sending,
    bool? stopping,
    bool? uncertain,
    bool? loaded,
    String? error,
    String? updatesError,
    Object? deletingConversationId = _unchanged,
    Object? deleteError = _unchanged,
  }) => ChatState(
    configuration: configuration ?? state.configuration,
    conversations: conversations ?? state.conversations,
    messages: messages ?? state.messages,
    selected: selected ?? state.selected,
    conversationCursor: identical(conversationCursor, _unchanged)
        ? state.conversationCursor
        : conversationCursor as String?,
    messageCursor: identical(messageCursor, _unchanged)
        ? state.messageCursor
        : messageCursor as String?,
    draft: draft ?? state.draft,
    loading: loading ?? state.loading,
    loadingHistory: loadingHistory ?? state.loadingHistory,
    loadingMessages: loadingMessages ?? state.loadingMessages,
    sending: sending ?? state.sending,
    stopping: stopping ?? state.stopping,
    uncertain: uncertain ?? state.uncertain,
    loaded: loaded ?? state.loaded,
    error: error,
    updatesError: updatesError,
    deletingConversationId: identical(deletingConversationId, _unchanged)
        ? state.deletingConversationId
        : deletingConversationId as String?,
    deleteError: identical(deleteError, _unchanged)
        ? state.deleteError
        : deleteError as String?,
  );
  static const _unchanged = Object();
  void _rememberDraft() => _drafts[state.selected?.id ?? ''] = state.draft;
  void _clearPending() {
    _pendingCreateId = null;
    _pendingRequestId = null;
    _pendingContent = null;
    _pendingConversationId = null;
  }

  void _stopSelection() {
    _selectionEpoch++;
    final cancel = _selectionCancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    _selectionCancel = null;
    _refreshing = false;
  }

  List<ChatConversation> _mergeConversations(
    List<ChatConversation> old,
    List<ChatConversation> incoming,
  ) =>
      {
        ...{for (final item in old) item.id: item},
        ...{for (final item in incoming) item.id: item},
      }.values.toList()..sort((a, b) {
        final compared = b.createdAt.compareTo(a.createdAt);
        return compared == 0 ? b.id.compareTo(a.id) : compared;
      });
  List<ChatMessage> _mergeMessages(
    List<ChatMessage> old,
    List<ChatMessage> incoming,
  ) => {
    ...{for (final item in old) item.id: item},
    ...{for (final item in incoming) item.id: item},
  }.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
  String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  Future<void> close() {
    _active = false;
    _historyEpoch++;
    _refresh.dispose();
    _stopSelection();
    return super.close();
  }
}
