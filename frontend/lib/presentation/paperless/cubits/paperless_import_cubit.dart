import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';
import '../../../domain/paperless/interfaces/paperless_repository.dart';
import '../../../domain/paperless/models/paperless.dart';
import '../models/paperless_import_state.dart';

final class PaperlessImportCubit extends Cubit<PaperlessImportState> {
  PaperlessImportCubit(this._repository, {String Function()? requestId})
    : _requestId = requestId ?? _newId,
      super(PaperlessImportState());
  final PaperlessRepository _repository;
  final String Function() _requestId;
  final _cancel = Completer<void>();
  bool _closed = false;
  bool _active = true;
  String? _pendingId;
  String? _cursor;
  bool _history = false;
  int _epoch = 0;
  bool _loading = false, _polling = false;
  Completer<void>? _readCancel;
  PaperlessConnection? _pendingConnection;

  static String _newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  late final _refresh = AutomaticRefresh(
    read: () => load(poll: true),
    busy: () => _loading || state.saving,
  )..setActive(true);
  void invalidate() => _refresh.invalidate();
  void setActive(bool active) {
    if (_closed || active == _active) return;
    _active = active;
    _refresh.setActive(active);
    _stopRead();
    emit(
      PaperlessImportState(
        options: state.options,
        runs: state.runs,
        cursor: _cursor,
        browsingHistory: _history,
        saving: state.saving,
        pendingRequest: _pendingId != null,
        error: state.error,
      ),
    );
    if (active) unawaited(load(poll: true));
  }

  void _stopRead() {
    _epoch++;
    _loading = false;
    if (_readCancel case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
  }

  Future<void> load({bool poll = false, bool more = false}) async {
    if (_closed || !_active || state.saving || (more && _cursor == null)) {
      return;
    }
    if (_loading && !poll && _polling) _stopRead();
    if (_loading) return;
    _loading = true;
    _polling = poll;
    final epoch = ++_epoch;
    final cancel = _readCancel = Completer<void>();
    bool current() => !_closed && _active && epoch == _epoch;
    emit(
      PaperlessImportState(
        cursor: _cursor,
        browsingHistory: _history,
        options: state.options,
        runs: state.runs,
        loading: !poll || state.options == null,
        pendingRequest: _pendingId != null,
        error: poll ? state.error : null,
      ),
    );
    try {
      final options =
          state.options ?? await _repository.options(cancel: cancel.future);
      if (!current()) return;
      final page = await _repository.runs(
        cursor: more ? _cursor : null,
        cancel: cancel.future,
      );
      if (!current()) return;
      var runs = page.items;
      if (poll && _history) {
        final updates = {for (final run in page.items) run.id: run};
        final active = state.runs
            .where((run) => run.active && !updates.containsKey(run.id))
            .toList();
        for (final run in active) {
          updates[run.id] = await _repository.get(
            run.id,
            cancel: cancel.future,
          );
          if (!current()) return;
        }
        runs = state.runs.map((run) => updates[run.id] ?? run).toList();
      } else {
        if (more) {
          final ids = state.runs.map((run) => run.id).toSet();
          runs = [...state.runs, ...runs.where((run) => ids.add(run.id))];
        }
        _cursor = page.nextCursor;
        _history = more;
      }
      if (!current()) return;
      if (runs.any((r) => r.id == _pendingId)) {
        _pendingId = null;
        _pendingConnection = null;
      }
      emit(
        PaperlessImportState(
          cursor: _cursor,
          browsingHistory: _history,
          options: options,
          runs: runs,
          pendingRequest: _pendingId != null,
        ),
      );
    } on PaperlessFailure catch (e) {
      if (current() && e.code != 'cancelled') {
        emit(
          PaperlessImportState(
            cursor: _cursor,
            browsingHistory: _history,
            options: state.options,
            runs: state.runs,
            pendingRequest: _pendingId != null,
            error: e.message,
          ),
        );
      }
    } finally {
      if (current()) {
        _loading = false;
      }
    }
  }

  Future<bool> start(PaperlessConnection connection) async {
    if (_closed || state.busy) return false;
    if (_pendingId == null) {
      final message = connection.validationMessage;
      if (message != null) {
        emit(
          PaperlessImportState(
            options: state.options,
            runs: state.runs,
            cursor: _cursor,
            browsingHistory: _history,
            error: message,
          ),
        );
        return false;
      }
      _pendingId = _requestId();
      _pendingConnection = connection;
    }
    _stopRead();
    emit(
      PaperlessImportState(
        cursor: _cursor,
        browsingHistory: _history,
        options: state.options,
        runs: state.runs,
        saving: true,
        pendingRequest: true,
      ),
    );
    try {
      final run = await _repository.start(
        _pendingId!,
        _pendingConnection!,
        cancel: _cancel.future,
      );
      if (_closed) return false;
      _pendingId = null;
      _pendingConnection = null;
      emit(
        PaperlessImportState(
          cursor: _cursor,
          browsingHistory: _history,
          options: state.options,
          runs: [run, ...state.runs.where((r) => r.id != run.id)],
        ),
      );
      return true;
    } on PaperlessFailure catch (e) {
      if (!e.uncertain) {
        _pendingId = null;
        _pendingConnection = null;
      }
      if (!_closed) {
        emit(
          PaperlessImportState(
            cursor: _cursor,
            browsingHistory: _history,
            options: state.options,
            runs: state.runs,
            pendingRequest: _pendingId != null,
            error: e.message,
          ),
        );
      }
      return false;
    }
  }

  Future<void> cancelRun(String id) async {
    if (_closed || state.busy) return;
    emit(
      PaperlessImportState(
        cursor: _cursor,
        browsingHistory: _history,
        options: state.options,
        runs: state.runs,
        saving: true,
        pendingRequest: _pendingId != null,
      ),
    );
    try {
      final run = await _repository.cancelRun(id, cancel: _cancel.future);
      if (!_closed) {
        emit(
          PaperlessImportState(
            cursor: _cursor,
            browsingHistory: _history,
            options: state.options,
            runs: state.runs.map((r) => r.id == id ? run : r),
            pendingRequest: _pendingId != null,
          ),
        );
      }
    } on PaperlessFailure catch (e) {
      if (!_closed) {
        emit(
          PaperlessImportState(
            cursor: _cursor,
            browsingHistory: _history,
            options: state.options,
            runs: state.runs,
            pendingRequest: _pendingId != null,
            error: e.message,
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    _refresh.dispose();
    _closed = true;
    _stopRead();
    _pendingConnection = null;
    _cancel.complete();
    return super.close();
  }
}
