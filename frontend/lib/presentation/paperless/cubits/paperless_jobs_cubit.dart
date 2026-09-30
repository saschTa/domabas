import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';
import '../../../domain/paperless/interfaces/paperless_repository.dart';
import '../../../domain/paperless/models/paperless.dart';

final class PaperlessJobsState {
  PaperlessJobsState({
    Map<String, int>? counts,
    this.countsRefreshing = false,
    this.countsError = false,
    Iterable<PaperlessRun> runs = const [],
    this.selected,
    this.cursor,
    this.status,
    this.browsingHistory = false,
    this.loading = false,
    this.error,
  }) : counts = counts == null ? null : Map.unmodifiable(counts),
       runs = List.unmodifiable(runs);

  final Map<String, int>? counts;
  final bool countsRefreshing, countsError;
  final List<PaperlessRun> runs;
  final PaperlessRun? selected;
  final bool loading, browsingHistory;
  final String? cursor, status;
  final String? error;
}

final class PaperlessJobsCubit extends Cubit<PaperlessJobsState> {
  PaperlessJobsCubit(this._repository, {required bool allowed})
    : allowed = allowed && _repository != null,
      super(PaperlessJobsState());

  final PaperlessRepository? _repository;
  final bool allowed;
  String? _status;
  bool _active = false, _loading = false, _polling = false;
  int _epoch = 0;
  bool _hasSnapshot = false;
  Completer<void>? _cancel;
  PaperlessRun? _selected;

  void filter(String? value) {
    if (isClosed || !allowed || value == _status) return;
    _status = value;
    _stopRead();
    emit(
      PaperlessJobsState(
        status: _status,
        selected: _selected,
        counts: state.counts,
        countsError: state.countsError,
      ),
    );
    if (_active) unawaited(load());
  }

  void selectJob(PaperlessRun run) {
    if (!allowed || !_active || isClosed) return;
    _selected = run;
    _publishSelection();
    unawaited(load(poll: true));
  }

  void clearSelection() {
    _selected = null;
    _publishSelection();
  }

  void _publishSelection() {
    if (isClosed) return;
    emit(
      PaperlessJobsState(
        counts: state.counts,
        countsRefreshing: state.countsRefreshing,
        countsError: state.countsError,
        status: _status,
        runs: state.runs,
        cursor: state.cursor,
        browsingHistory: state.browsingHistory,
        selected: _selected,
        loading: state.loading,
        error: state.error,
      ),
    );
  }

  late final _refresh = AutomaticRefresh(
    read: () => load(poll: true),
    busy: () => _loading,
  );
  void invalidate() => _refresh.invalidate();
  void setActive(bool active) {
    if (isClosed || !allowed || _active == active) return;
    _active = active;
    _refresh.setActive(active);
    _stopRead();
    if (active) unawaited(load(poll: true));
  }

  void _stopRead() {
    _epoch++;
    if (_cancel case final cancel? when !cancel.isCompleted) cancel.complete();
    _loading = false;
  }

  Future<void> load({bool poll = false, bool more = false}) async {
    if (!allowed || !_active || isClosed) return;
    if (!poll && _loading && _polling) _stopRead();
    if (_loading || (more && state.cursor == null)) return;
    final previous = state;
    final epoch = ++_epoch;
    final cancel = _cancel = Completer<void>();
    _loading = true;
    _polling = poll;
    emit(
      PaperlessJobsState(
        counts: state.counts,
        countsRefreshing: true,
        countsError: state.countsError,
        status: _status,
        runs: previous.runs,
        cursor: previous.cursor,
        browsingHistory: previous.browsingHistory,
        selected: _selected,
        loading: !poll || !_hasSnapshot,
        error: poll ? previous.error : null,
      ),
    );
    bool current() => !isClosed && _active && epoch == _epoch;
    try {
      final page = await _repository!.runs(
        cursor: more ? previous.cursor : null,
        status: _status,
        cancel: cancel.future,
      );
      if (!current()) return;
      final selectedId = _selected?.id;
      if (selectedId != null) {
        final selected = await _repository.get(
          selectedId,
          cancel: cancel.future,
        );
        if (!current()) return;
        if (_selected?.id == selectedId) _selected = selected;
      }
      var runs = page.items;
      var cursor = page.nextCursor;
      if (poll && previous.browsingHistory) {
        final updates = {for (final run in page.items) run.id: run};
        final active = previous.runs
            .where((run) => run.active && !updates.containsKey(run.id))
            .toList();
        for (final run in active) {
          updates[run.id] = await _repository.get(
            run.id,
            cancel: cancel.future,
          );
          if (!current()) return;
        }
        runs = previous.runs.map((run) => updates[run.id] ?? run).toList();
        cursor = previous.cursor;
      } else if (more) {
        final ids = previous.runs.map((run) => run.id).toSet();
        runs = [...previous.runs, ...runs.where((run) => ids.add(run.id))];
      }
      _hasSnapshot = true;
      emit(
        PaperlessJobsState(
          counts: page.counts,
          countsRefreshing: false,
          countsError: false,
          status: _status,
          runs: runs.where((run) => _status == null || run.status == _status),
          selected: _selected,
          cursor: cursor,
          browsingHistory: more || (poll && previous.browsingHistory),
        ),
      );
    } on PaperlessFailure catch (failure) {
      if (current() && failure.code != 'cancelled') {
        emit(
          PaperlessJobsState(
            counts: state.counts,
            countsRefreshing: false,
            countsError: true,
            status: _status,
            runs: previous.runs,
            cursor: previous.cursor,
            browsingHistory: previous.browsingHistory,
            selected: _selected,
            error: failure.message,
          ),
        );
      }
    } finally {
      if (current()) {
        _loading = false;
      }
    }
  }

  @override
  Future<void> close() {
    _refresh.dispose();
    _active = false;
    _stopRead();
    return super.close();
  }
}
