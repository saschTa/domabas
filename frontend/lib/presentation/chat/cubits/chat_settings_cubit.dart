import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/chat/interfaces/chat_repository.dart';
import '../../../domain/chat/models/chat.dart';

final class ChatSettingsState {
  ChatSettingsState({
    this.saved,
    this.draft = const ChatConfigurationDraft(),
    this.loading = false,
    this.saving = false,
    this.requiresRefresh = false,
    this.error,
    this.notice,
  });
  final ChatConfiguration? saved;
  final ChatConfigurationDraft draft;
  final bool loading, saving, requiresRefresh;
  final String? error, notice;
  bool get dirty => saved != null && draft.changed(saved!);
  bool get canSave =>
      dirty && draft.error == null && !loading && !saving && !requiresRefresh;
}

final class ChatSettingsCubit extends Cubit<ChatSettingsState> {
  ChatSettingsCubit(this._repository, {required bool allowed})
    : allowed = allowed && _repository != null,
      super(ChatSettingsState());
  final ChatRepository? _repository;
  final bool allowed;
  bool _active = false;
  int _epoch = 0;
  void setActive(bool value) {
    if (isClosed || !allowed || _active == value) return;
    _active = value;
    if (value) unawaited(load());
  }

  Future<void> load() async {
    if (isClosed || !_active || state.loading || state.saving) return;
    final epoch = ++_epoch;
    final keep = state.dirty;
    emit(_state(loading: true));
    try {
      final saved = await _repository!.configuration(admin: true);
      if (isClosed || epoch != _epoch) return;
      emit(
        _state(
          saved: saved,
          loading: false,
          draft: keep || state.dirty
              ? state.draft
              : ChatConfigurationDraft.saved(saved),
          requiresRefresh: false,
        ),
      );
    } on ChatFailure catch (failure) {
      if (!isClosed && epoch == _epoch) {
        emit(_state(loading: false, error: failure.message));
      }
    }
  }

  void edit({
    bool? enabled,
    bool? thinkingEnabled,
    String? provider,
    String? model,
    String? baseUrl,
    String? apiKey,
    bool? clearApiKey,
  }) {
    if (!_active || isClosed || state.saving) return;
    emit(
      _state(
        draft: state.draft.copyWith(
          enabled: enabled,
          thinkingEnabled: thinkingEnabled,
          provider: provider,
          model: model,
          baseUrl: baseUrl,
          apiKey: apiKey,
          clearApiKey: clearApiKey,
        ),
      ),
    );
  }

  void reset() {
    if (!isClosed && !state.saving && state.saved != null) {
      emit(_state(draft: ChatConfigurationDraft.saved(state.saved!)));
    }
  }

  Future<void> save() async {
    if (isClosed || !_active || !state.canSave) return;
    final epoch = ++_epoch;
    emit(_state(saving: true));
    try {
      final saved = await _repository!.updateConfiguration(
        state.draft,
        expectedRevision: state.saved!.revision,
      );
      if (isClosed || epoch != _epoch) return;
      emit(
        _state(
          saved: saved,
          saving: false,
          draft: ChatConfigurationDraft.saved(saved),
          notice: 'AI chat settings saved.',
        ),
      );
    } on ChatFailure catch (failure) {
      if (!isClosed && epoch == _epoch) {
        emit(
          _state(
            saving: false,
            error: failure.message,
            requiresRefresh: failure.code != 'invalid_request',
          ),
        );
      }
    }
  }

  ChatSettingsState _state({
    ChatConfiguration? saved,
    ChatConfigurationDraft? draft,
    bool? loading,
    bool? saving,
    bool? requiresRefresh,
    String? error,
    String? notice,
  }) {
    return ChatSettingsState(
      saved: saved ?? state.saved,
      draft: draft ?? state.draft,
      loading: loading ?? state.loading,
      saving: saving ?? state.saving,
      requiresRefresh: requiresRefresh ?? state.requiresRefresh,
      error: error,
      notice: notice,
    );
  }

  @override
  Future<void> close() {
    _active = false;
    _epoch++;
    return super.close();
  }
}
