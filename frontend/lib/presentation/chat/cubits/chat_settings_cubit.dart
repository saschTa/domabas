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
    this.loadingModels = false,
    this.requiresRefresh = false,
    this.error,
    this.notice,
    this.modelsError,
    Iterable<String> models = const [],
    this.nextModelOffset,
    this.modelContext,
    this.loadingModelContext = false,
    this.modelContextError,
  }) : models = List.unmodifiable(models);
  final ChatConfiguration? saved;
  final ChatConfigurationDraft draft;
  final bool loading, saving, loadingModels, requiresRefresh;
  final String? error, notice, modelsError;
  final List<String> models;
  final int? nextModelOffset;
  final ChatModelContext? modelContext;
  final bool loadingModelContext;
  final String? modelContextError;
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
  int _contextEpoch = 0;
  Completer<void>? _contextCancel;
  ChatModelContext? _modelContext;
  bool _loadingModelContext = false;
  String? _modelContextError;
  void setActive(bool value) {
    if (isClosed || !allowed || _active == value) return;
    _active = value;
    if (!value) _clearModelContext();
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
      if (state.models.isEmpty) unawaited(loadModels());
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
    String? contextLength,
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
          contextLength: contextLength,
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

  Future<void> loadModels({bool more = false}) async {
    if (isClosed ||
        !_active ||
        state.loadingModels ||
        (more && state.nextModelOffset == null)) {
      return;
    }
    emit(_state(loadingModels: true));
    try {
      final page = await _repository!.models(
        offset: more ? state.nextModelOffset! : 0,
      );
      if (isClosed) return;
      emit(
        _state(
          loadingModels: false,
          models: {if (more) ...state.models, ...page.items}.toList(),
          nextModelOffset: page.nextOffset,
        ),
      );
    } on ChatFailure catch (_) {
      if (!isClosed) {
        emit(
          _state(
            loadingModels: false,
            modelsError: 'Installed models could not be loaded. You can still enter a model name.',
          ),
        );
      }
    }
  }

  Future<void> checkModelContext() async {
    final model = state.draft.model.trim();
    if (isClosed ||
        !_active ||
        state.saving ||
        _loadingModelContext ||
        state.draft.provider != 'ollama' ||
        model.isEmpty) {
      return;
    }
    _clearModelContext();
    final epoch = _contextEpoch;
    final cancel = _contextCancel = Completer<void>();
    _loadingModelContext = true;
    emit(
      _state(
        error: state.error,
        notice: state.notice,
        modelsError: state.modelsError,
      ),
    );
    try {
      final result = await _repository!.modelContext(
        model,
        cancel: cancel.future,
      );
      if (isClosed || !_active || epoch != _contextEpoch) return;
      _modelContext = result;
    } on ChatFailure catch (_) {
      if (isClosed || !_active || epoch != _contextEpoch) return;
      _modelContextError = 'Could not check this model’s context limit. Check that the model is installed, then retry.';
    } finally {
      if (!isClosed && _active && epoch == _contextEpoch) {
        _loadingModelContext = false;
        emit(
          _state(
            error: state.error,
            notice: state.notice,
            modelsError: state.modelsError,
          ),
        );
      }
    }
  }

  void _clearModelContext() {
    _contextEpoch++;
    if (_contextCancel != null && !_contextCancel!.isCompleted) {
      _contextCancel!.complete();
    }
    _modelContext = null;
    _loadingModelContext = false;
    _modelContextError = null;
  }

  ChatSettingsState _state({
    ChatConfiguration? saved,
    ChatConfigurationDraft? draft,
    bool? loading,
    bool? saving,
    bool? loadingModels,
    bool? requiresRefresh,
    String? error,
    String? notice,
    String? modelsError,
    List<String>? models,
    Object? nextModelOffset = _unchanged,
  }) {
    final nextDraft = draft ?? state.draft;
    if (nextDraft.model.trim() != state.draft.model.trim() ||
        nextDraft.provider != state.draft.provider) {
      _clearModelContext();
    }
    return ChatSettingsState(
      saved: saved ?? state.saved,
      draft: draft ?? state.draft,
      loading: loading ?? state.loading,
      saving: saving ?? state.saving,
      loadingModels: loadingModels ?? state.loadingModels,
      requiresRefresh: requiresRefresh ?? state.requiresRefresh,
      error: error,
      notice: notice,
      modelsError: modelsError,
      models: models ?? state.models,
      nextModelOffset: identical(nextModelOffset, _unchanged)
          ? state.nextModelOffset
          : nextModelOffset as int?,
      modelContext: _modelContext,
      loadingModelContext: _loadingModelContext,
      modelContextError: _modelContextError,
    );
  }

  static const _unchanged = Object();
  @override
  Future<void> close() {
    _active = false;
    _epoch++;
    _clearModelContext();
    return super.close();
  }
}
