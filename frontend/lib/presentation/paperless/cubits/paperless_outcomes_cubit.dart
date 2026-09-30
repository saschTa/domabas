import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';
import '../../../domain/paperless/interfaces/paperless_repository.dart';
import '../../../domain/paperless/models/paperless.dart';

final class PaperlessOutcomesState {
  PaperlessOutcomesState({
    Iterable<PaperlessOutcome> items = const [],
    this.cursor,
    this.loading = false,
    this.error,
    this.status,
  }) : items = List.unmodifiable(items);
  final List<PaperlessOutcome> items;
  final String? cursor, error, status;
  final bool loading;
}

final class PaperlessOutcomesCubit extends Cubit<PaperlessOutcomesState> {
  PaperlessOutcomesCubit(this._repository, this.runId)
    : super(PaperlessOutcomesState());
  final PaperlessRepository _repository;
  final String runId;
  Completer<void>? _cancel;
  bool _loading = false, _automatic = false, _hasSnapshot = false;
  int _epoch = 0, _pages = 1;
  late final _refresh = AutomaticRefresh(
    read: () => load(automatic: true),
    busy: () => _loading,
  )..setActive(true);
  void invalidate() => _refresh.invalidate();

  Future<void> setStatus(String? status) async {
    if (isClosed || status == state.status) return;
    _epoch++;
    if (_cancel case final cancel? when !cancel.isCompleted) cancel.complete();
    _loading = false;
    _pages = 1;
    _hasSnapshot = false;
    emit(PaperlessOutcomesState(status: status));
    await load();
  }

  Future<void> load({bool more = false, bool automatic = false}) async {
    if (isClosed || (more && state.cursor == null)) {
      return;
    }
    if (_loading) {
      if (automatic || !_automatic) return;
      _cancel?.complete();
    }
    _loading = true;
    _automatic = automatic;
    final epoch = ++_epoch;
    final cancel = _cancel = Completer<void>();
    bool current() => !isClosed && epoch == _epoch;
    final previous = state;
    emit(
      PaperlessOutcomesState(
        items: previous.items,
        cursor: previous.cursor,
        loading: !automatic || !_hasSnapshot,
        error: automatic ? previous.error : null,
        status: previous.status,
      ),
    );
    try {
      var page = await _repository.outcomes(
        runId,
        cursor: more ? previous.cursor : null,
        status: previous.status,
        cancel: cancel.future,
      );
      if (!current()) return;
      final items = {
        if (more)
          for (final item in previous.items) item.sourceId: item,
        for (final item in page.items) item.sourceId: item,
      };
      var pages = 1;
      final seen = <String>{};
      while (automatic && page.nextCursor != null && pages < _pages) {
        if (!seen.add(page.nextCursor!)) {
          throw const PaperlessFailure('invalid_response');
        }
        page = await _repository.outcomes(
          runId,
          cursor: page.nextCursor,
          status: previous.status,
          cancel: cancel.future,
        );
        if (!current()) return;
        for (final item in page.items) {
          items[item.sourceId] = item;
        }
        pages++;
      }
      _pages = more ? _pages + 1 : pages;
      _hasSnapshot = true;
      emit(
        PaperlessOutcomesState(
          items: items.values,
          cursor: page.nextCursor,
          status: previous.status,
        ),
      );
    } on PaperlessFailure catch (failure) {
      if (current() && failure.code != 'cancelled') {
        emit(
          PaperlessOutcomesState(
            items: previous.items,
            cursor: previous.cursor,
            error: failure.message,
            status: previous.status,
          ),
        );
      }
    } finally {
      if (current()) _loading = false;
    }
  }

  @override
  Future<void> close() {
    _refresh.dispose();
    _epoch++;
    if (_cancel case final cancel? when !cancel.isCompleted) cancel.complete();
    return super.close();
  }
}
