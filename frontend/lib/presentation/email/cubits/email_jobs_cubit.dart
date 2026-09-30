import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/email/interfaces/email_repository.dart';
import '../../../domain/email/models/email.dart';
import '../../../scheduling/automatic_refresh.dart';

final class EmailJobsState {
  EmailJobsState({
    Map<String, int>? counts,
    this.countsRefreshing = false,
    this.countsError = false,
    Iterable<EmailRun> runs = const [],
    Iterable<EmailProvider> providers = const [],
    this.cursor,
    this.status,
    this.selected,
    this.loading = false,
    this.browsingHistory = false,
    this.error,
  }) : counts = counts == null ? null : Map.unmodifiable(counts),
       runs = List.unmodifiable(runs),
       providers = List.unmodifiable(providers);

  final Map<String, int>? counts;
  final bool countsRefreshing, countsError;
  final List<EmailRun> runs;
  final EmailRun? selected;
  final List<EmailProvider> providers;
  final String? cursor, error, status;
  final bool loading, browsingHistory;
}

final class EmailJobsCubit extends Cubit<EmailJobsState> {
  EmailJobsCubit(this._repository, {required this.allowed})
    : super(EmailJobsState());

  final EmailRepository _repository;
  final bool allowed;
  String? _status;
  bool _active = false, _loading = false, _polling = false;
  EmailRun? _selected;
  int _epoch = 0;
  Completer<void>? _cancel;
  late final _refresh = AutomaticRefresh(
    read: () => load(poll: true),
    busy: () => _loading,
    interval: () => Duration(seconds: state.error == null ? 1 : 30),
  );

  void filter(String? value) {
    if (isClosed || !allowed || value == _status) return;
    _status = value;
    _stopRead();
    emit(
      EmailJobsState(
        counts: state.counts,
        countsRefreshing: state.countsRefreshing,
        countsError: state.countsError,
        status: _status,
        selected: _selected,
        providers: state.providers,
      ),
    );
    if (_active) unawaited(load());
  }

  void selectJob(EmailRun run) {
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
      EmailJobsState(
        counts: state.counts,
        countsRefreshing: state.countsRefreshing,
        countsError: state.countsError,
        status: _status,
        runs: state.runs,
        providers: state.providers,
        cursor: state.cursor,
        loading: state.loading,
        browsingHistory: state.browsingHistory,
        error: state.error,
        selected: _selected,
      ),
    );
  }

  void invalidate() => _refresh.invalidate();

  void setActive(bool value) {
    if (isClosed || !allowed || _active == value) return;
    _active = value;
    _refresh.setActive(value);
    _stopRead();
    if (value) unawaited(load(poll: true));
  }

  void _stopRead() {
    _epoch++;
    if (_cancel case final cancel? when !cancel.isCompleted) cancel.complete();
    _loading = false;
  }

  Future<void> load({bool more = false, bool poll = false}) async {
    if (!allowed || !_active || isClosed) return;
    if (!poll && _loading && _polling) _stopRead();
    if (_loading || (more && state.cursor == null)) return;
    final previous = state;
    final epoch = ++_epoch;
    final cancel = _cancel = Completer<void>();
    _loading = true;
    _polling = poll;
    emit(
      EmailJobsState(
        counts: state.counts,
        countsRefreshing: true,
        countsError: state.countsError,
        status: _status,
        selected: _selected,
        runs: previous.runs,
        providers: previous.providers,
        cursor: previous.cursor,
        browsingHistory: previous.browsingHistory,
        loading: !poll || previous.runs.isEmpty,
        error: poll ? previous.error : null,
      ),
    );
    bool current() => !isClosed && _active && epoch == _epoch;
    try {
      final page = await _repository.listRuns(
        null,
        cursor: more ? previous.cursor : null,
        status: _status,
        cancel: cancel.future,
      );
      if (!current()) return;
      final providers = await _repository.listProviders(
        limit: 50,
        cancel: cancel.future,
      );
      if (!current()) return;
      final selectedId = _selected?.id;
      if (selectedId != null) {
        final selected = await _repository.getRun(
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
          updates[run.id] = await _repository.getRun(
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
      emit(
        EmailJobsState(
          counts: page.counts,
          countsRefreshing: false,
          countsError: false,
          status: _status,
          selected: _selected,
          runs: runs.where((run) => _status == null || run.status == _status),
          providers: providers.items,
          cursor: cursor,
          browsingHistory: more || (poll && previous.browsingHistory),
        ),
      );
    } on EmailFailure catch (failure) {
      if (current() && failure.kind != EmailFailureKind.cancelled) {
        emit(
          EmailJobsState(
            counts: state.counts,
            countsRefreshing: false,
            countsError: true,
            status: _status,
            selected: _selected,
            runs: previous.runs,
            providers: previous.providers,
            cursor: previous.cursor,
            browsingHistory: previous.browsingHistory,
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
    _active = false;
    _refresh.dispose();
    _stopRead();
    return super.close();
  }
}
