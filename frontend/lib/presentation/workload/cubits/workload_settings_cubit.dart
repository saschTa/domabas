import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/workload/interfaces/workload_settings_repository.dart';
import '../../../domain/workload/models/workload_settings.dart';

final class WorkloadSettingsState {
  WorkloadSettingsState({
    this.settings,
    Map<String, String> drafts = const {},
    this.loading = false,
    this.saving = false,
    this.requiresRefresh = false,
    this.draftGeneration = 0,
    this.error,
    this.notice,
  }) : drafts = Map.unmodifiable(drafts);

  final WorkloadSettings? settings;
  final Map<String, String> drafts;
  final bool loading, saving, requiresRefresh;
  final int draftGeneration;
  final String? error, notice;

  bool get dirty =>
      settings?.resources.any(
        (resource) => drafts[resource.id] != resource.limit.toString(),
      ) ??
      false;
  bool get valid =>
      settings?.resources.every(
        (resource) => resource.validateLimit(drafts[resource.id] ?? '') == null,
      ) ??
      false;
  bool get canSave => dirty && valid && !loading && !saving && !requiresRefresh;
}

final class WorkloadSettingsCubit extends Cubit<WorkloadSettingsState> {
  WorkloadSettingsCubit(this._repository, {required bool allowed})
    : allowed = allowed && _repository != null,
      super(WorkloadSettingsState());

  final WorkloadSettingsRepository? _repository;
  final bool allowed;
  bool _active = false;
  int _epoch = 0;
  Completer<void>? _cancel;

  void setActive(bool value) {
    if (isClosed || !allowed || value == _active) return;
    _active = value;
    if (value) {
      unawaited(load());
    } else if (state.loading) {
      _stop();
      emit(_state());
    }
  }

  void edit(String resourceId, String value) {
    if (!allowed ||
        !_active ||
        isClosed ||
        state.loading ||
        state.saving ||
        state.settings == null ||
        !state.drafts.containsKey(resourceId)) {
      return;
    }
    emit(
      _state(drafts: {...state.drafts, resourceId: value}, error: state.error),
    );
  }

  void resetDraft() {
    if (!allowed ||
        !_active ||
        isClosed ||
        state.loading ||
        state.saving ||
        state.requiresRefresh ||
        state.settings == null) {
      return;
    }
    emit(
      WorkloadSettingsState(
        settings: state.settings,
        drafts: _savedDrafts(state.settings!),
        draftGeneration: state.draftGeneration + 1,
      ),
    );
  }

  Future<void> load() async {
    if (!allowed || !_active || isClosed || state.loading || state.saving) {
      return;
    }
    final epoch = ++_epoch;
    final cancel = _cancel = Completer<void>();
    final edits = <String, String>{
      for (final resource in state.settings?.resources ?? <WorkloadResource>[])
        if (state.drafts[resource.id] != resource.limit.toString())
          resource.id: state.drafts[resource.id] ?? '',
    };
    emit(_state(loading: true));
    try {
      final settings = await _repository!.settings(cancel: cancel.future);
      if (isClosed || epoch != _epoch) return;
      emit(
        WorkloadSettingsState(
          settings: settings,
          drafts: {
            for (final resource in settings.resources)
              resource.id: edits[resource.id] ?? resource.limit.toString(),
          },
          draftGeneration: state.draftGeneration + 1,
        ),
      );
    } on WorkloadSettingsFailure catch (failure) {
      if (!isClosed && epoch == _epoch) emit(_state(error: failure.message));
    }
  }

  Future<void> save() async {
    if (!allowed || !_active || isClosed || !state.canSave) return;
    final epoch = ++_epoch;
    final cancel = _cancel = Completer<void>();
    emit(_state(saving: true));
    try {
      final settings = await _repository!.updateSettings(
        limits: {
          for (final resource in state.settings!.resources)
            resource.id: int.parse(state.drafts[resource.id]!.trim()),
        },
        expectedRevision: state.settings!.revision,
        cancel: cancel.future,
      );
      if (isClosed || epoch != _epoch) return;
      emit(
        WorkloadSettingsState(
          settings: settings,
          drafts: _savedDrafts(settings),
          draftGeneration: state.draftGeneration + 1,
          notice: 'Workload limits saved.',
        ),
      );
    } on WorkloadSettingsFailure catch (failure) {
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

  Map<String, String> _savedDrafts(WorkloadSettings settings) => {
    for (final resource in settings.resources)
      resource.id: resource.limit.toString(),
  };

  WorkloadSettingsState _state({
    Map<String, String>? drafts,
    bool loading = false,
    bool saving = false,
    bool? requiresRefresh,
    String? error,
  }) => WorkloadSettingsState(
    settings: state.settings,
    drafts: drafts ?? state.drafts,
    loading: loading,
    saving: saving,
    requiresRefresh: requiresRefresh ?? state.requiresRefresh,
    draftGeneration: state.draftGeneration,
    error: error,
  );

  void _stop() {
    _epoch++;
    if (_cancel case final cancel? when !cancel.isCompleted) cancel.complete();
  }

  @override
  Future<void> close() {
    _active = false;
    _stop();
    return super.close();
  }
}
