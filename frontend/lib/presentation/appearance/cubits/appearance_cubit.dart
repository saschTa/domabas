import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/appearance/interfaces/appearance_repository.dart';
import '../../../domain/appearance/models/appearance_preference.dart';

enum AppearanceIssue {
  restoreUnavailable,
  restorePending,
  saveUnavailable,
  savePending,
}

final class AppearanceState {
  const AppearanceState({
    this.preference = AppearancePreference.system,
    this.restoring = false,
    this.saving = false,
    this.issue,
    this.canRetry = false,
  });

  final AppearancePreference preference;
  final bool restoring;
  final bool saving;
  final AppearanceIssue? issue;
  final bool canRetry;
}

final class AppearanceCubit extends Cubit<AppearanceState> {
  AppearanceCubit(
    this._repository, {
    this.operationTimeout = const Duration(seconds: 2),
  }) : super(const AppearanceState());

  final AppearanceRepository _repository;
  final Duration operationTimeout;
  Timer? _readTimer;
  Timer? _writeTimer;
  bool _closing = false;
  bool _reading = false;
  bool _readTimedOut = false;
  bool _writeTimedOut = false;
  bool _selectedExplicitly = false;
  int _revision = 0;
  _AppearanceWriteIntent? _activeWrite;
  _AppearanceWriteIntent? _pendingWrite;

  void restore() {
    if (_closing || _reading || _selectedExplicitly) return;
    _reading = true;
    _readTimedOut = false;
    emit(AppearanceState(preference: state.preference, restoring: true));
    _readTimer = Timer(operationTimeout, () {
      if (_closing || !_reading || _selectedExplicitly) return;
      _readTimedOut = true;
      emit(
        AppearanceState(
          preference: state.preference,
          issue: AppearanceIssue.restorePending,
        ),
      );
    });
    unawaited(
      Future<AppearancePreference>.sync(_repository.read).then(
        (preference) => _finishRead(preference),
        onError: (Object _, StackTrace _) => _finishRead(null),
      ),
    );
  }

  void _finishRead(AppearancePreference? preference) {
    _reading = false;
    _readTimer?.cancel();
    _readTimer = null;
    if (_closing || _selectedExplicitly) return;
    if (_readTimedOut || preference == null) {
      emit(
        AppearanceState(
          preference: state.preference,
          issue: AppearanceIssue.restoreUnavailable,
          canRetry: true,
        ),
      );
      return;
    }
    emit(AppearanceState(preference: preference));
  }

  void select(AppearancePreference preference) {
    if (_closing) return;
    _selectedExplicitly = true;
    _readTimer?.cancel();
    _readTimer = null;
    _pendingWrite = _AppearanceWriteIntent(preference, ++_revision);
    final waiting = _activeWrite != null && _writeTimedOut;
    emit(
      AppearanceState(
        preference: preference,
        saving: !waiting,
        issue: waiting ? AppearanceIssue.savePending : null,
      ),
    );
    _drainWrite();
  }

  void _drainWrite() {
    if (_closing || _activeWrite != null) return;
    final intent = _pendingWrite;
    if (intent == null) return;
    _pendingWrite = null;
    _activeWrite = intent;
    _writeTimedOut = false;
    emit(AppearanceState(preference: state.preference, saving: true));
    _writeTimer = Timer(operationTimeout, () {
      if (_closing || !identical(_activeWrite, intent)) return;
      _writeTimedOut = true;
      emit(
        AppearanceState(
          preference: state.preference,
          issue: AppearanceIssue.savePending,
        ),
      );
    });
    unawaited(
      Future<void>.sync(() => _repository.write(intent.preference)).then(
        (_) => _finishWrite(intent, succeeded: true),
        onError: (Object _, StackTrace _) =>
            _finishWrite(intent, succeeded: false),
      ),
    );
  }

  void _finishWrite(_AppearanceWriteIntent intent, {required bool succeeded}) {
    if (!identical(_activeWrite, intent)) return;
    _writeTimer?.cancel();
    _writeTimer = null;
    _activeWrite = null;
    _writeTimedOut = false;
    if (_closing) return;
    if (_pendingWrite != null) {
      _drainWrite();
      return;
    }
    if (intent.revision != _revision) return;
    emit(
      AppearanceState(
        preference: state.preference,
        issue: succeeded ? null : AppearanceIssue.saveUnavailable,
        canRetry: !succeeded,
      ),
    );
  }

  void retry() {
    if (_closing || !state.canRetry) return;
    if (_selectedExplicitly) {
      select(state.preference);
    } else {
      restore();
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _readTimer?.cancel();
    _writeTimer?.cancel();
    _readTimer = null;
    _writeTimer = null;
    _pendingWrite = null;
    return super.close();
  }
}

final class _AppearanceWriteIntent {
  const _AppearanceWriteIntent(this.preference, this.revision);

  final AppearancePreference preference;
  final int revision;
}
