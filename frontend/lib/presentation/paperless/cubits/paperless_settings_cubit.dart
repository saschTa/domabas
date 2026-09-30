import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/paperless/interfaces/paperless_settings_repository.dart';
import '../../../domain/paperless/models/paperless_settings.dart';

final class PaperlessSettingsState {
  const PaperlessSettingsState({
    this.settings,
    this.retrievalConcurrency = 1,
    this.loading = false,
    this.saving = false,
    this.requiresRefresh = false,
    this.error,
    this.notice,
  });

  final PaperlessSettings? settings;
  final int retrievalConcurrency;
  final bool loading, saving, requiresRefresh;
  final String? error, notice;

  bool get dirty =>
      settings != null &&
      retrievalConcurrency != settings!.retrievalConcurrency;
  bool get canSave => dirty && !loading && !saving && !requiresRefresh;
}

final class PaperlessSettingsCubit extends Cubit<PaperlessSettingsState> {
  PaperlessSettingsCubit(this._repository, {required bool allowed})
    : allowed = allowed && _repository != null,
      super(const PaperlessSettingsState());

  final PaperlessSettingsRepository? _repository;
  final bool allowed;
  bool _active = false;
  int _epoch = 0;
  Completer<void>? _cancel;

  void setActive(bool active) {
    if (isClosed || !allowed || active == _active) return;
    _active = active;
    if (active) {
      unawaited(load());
    } else if (state.loading) {
      _stop();
      emit(_state());
    }
  }

  void edit(int value) {
    final settings = state.settings;
    if (!allowed ||
        !_active ||
        isClosed ||
        settings == null ||
        state.loading ||
        state.saving ||
        value < settings.minimumRetrievalConcurrency ||
        value > settings.maximumRetrievalConcurrency) {
      return;
    }
    emit(_state(retrievalConcurrency: value, error: state.error));
  }

  Future<void> load() async {
    if (!allowed || !_active || isClosed || state.loading || state.saving) {
      return;
    }
    final epoch = ++_epoch;
    final cancel = _cancel = Completer<void>();
    final keepDraft = state.dirty;
    emit(_state(loading: true));
    try {
      final settings = await _repository!.settings(cancel: cancel.future);
      if (isClosed || epoch != _epoch) return;
      final draft = state.retrievalConcurrency;
      final validDraft =
          draft >= settings.minimumRetrievalConcurrency &&
          draft <= settings.maximumRetrievalConcurrency;
      emit(
        PaperlessSettingsState(
          settings: settings,
          retrievalConcurrency: keepDraft && validDraft
              ? draft
              : settings.retrievalConcurrency,
        ),
      );
    } on PaperlessSettingsFailure catch (failure) {
      if (!isClosed && epoch == _epoch) {
        emit(_state(error: failure.message));
      }
    }
  }

  Future<void> save() async {
    if (!allowed || !_active || isClosed || !state.canSave) return;
    final epoch = ++_epoch;
    final cancel = _cancel = Completer<void>();
    emit(_state(saving: true));
    try {
      final settings = await _repository!.updateSettings(
        retrievalConcurrency: state.retrievalConcurrency,
        expectedRevision: state.settings!.revision,
        cancel: cancel.future,
      );
      if (isClosed || epoch != _epoch) return;
      emit(
        PaperlessSettingsState(
          settings: settings,
          retrievalConcurrency: settings.retrievalConcurrency,
          notice: 'Paperless retrieval settings saved.',
        ),
      );
    } on PaperlessSettingsFailure catch (failure) {
      if (!isClosed && epoch == _epoch) {
        emit(
          _state(
            error: failure.message,
            requiresRefresh: failure.code != 'invalid_request',
          ),
        );
      }
    }
  }

  PaperlessSettingsState _state({
    int? retrievalConcurrency,
    bool loading = false,
    bool saving = false,
    bool? requiresRefresh,
    String? error,
  }) => PaperlessSettingsState(
    settings: state.settings,
    retrievalConcurrency: retrievalConcurrency ?? state.retrievalConcurrency,
    loading: loading,
    saving: saving,
    requiresRefresh: requiresRefresh ?? state.requiresRefresh,
    error: error,
  );

  void _stop() {
    _epoch++;
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  @override
  Future<void> close() {
    _active = false;
    _stop();
    return super.close();
  }
}
