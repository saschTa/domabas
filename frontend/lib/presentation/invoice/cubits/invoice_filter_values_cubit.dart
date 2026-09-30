import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/invoice/interfaces/invoice_repository.dart';
import '../../../domain/invoice/models/invoice.dart';
import '../../../domain/invoice/models/invoice_search.dart';

final class InvoiceFilterValuesState {
  InvoiceFilterValuesState({
    this.query = '',
    Iterable<String> items = const [],
    this.nextCursor,
    this.loading = false,
    this.debouncing = false,
    this.loaded = false,
    this.blocked = false,
    this.error,
    this.validation,
    this.page = 1,
    this.hasPrevious = false,
  }) : items = List.unmodifiable(items);

  final String query;
  final List<String> items;
  final String? nextCursor, error, validation;
  final bool loading, debouncing, loaded, blocked, hasPrevious;
  final int page;
  bool get busy => loading || debouncing || blocked;
}

final class InvoiceFilterValuesCubit extends Cubit<InvoiceFilterValuesState> {
  InvoiceFilterValuesCubit(this._repository, this.field)
    : super(InvoiceFilterValuesState());

  final InvoiceRepository _repository;
  final InvoiceFilterField field;
  final _previous = <String?>[];
  String? _cursor;
  String _rawQuery = '';
  bool _composing = false;
  int _generation = 0;
  Timer? _debounce;
  Completer<void>? _cancel;
  (String?, int, bool, bool, bool)? _failed;

  void _stop() {
    _generation++;
    _debounce?.cancel();
    _debounce = null;
    if (_cancel case final cancel? when !cancel.isCompleted) cancel.complete();
  }

  void editQuery(String raw, {required bool composing}) {
    if (isClosed || raw == _rawQuery && composing == _composing) return;
    _rawQuery = raw;
    _composing = composing;
    _stop();
    _previous.clear();
    _cursor = null;
    _failed = null;
    final query = raw.trim();
    final validation = query.runes.length > 200
        ? 'Use 200 characters or fewer.'
        : query.contains('\u0000')
        ? 'Remove invalid text characters.'
        : null;
    final blocked = composing || validation != null;
    emit(
      InvoiceFilterValuesState(
        query: query,
        blocked: blocked,
        validation: validation,
        debouncing: !blocked,
      ),
    );
    if (blocked) return;
    final generation = _generation;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!isClosed && generation == _generation) unawaited(submit());
    });
  }

  Future<void> submit() => _load(null, 1, restart: true);
  Future<void> retry() {
    final failed = _failed;
    return failed == null
        ? _load(_cursor, state.page)
        : _load(
            failed.$1,
            failed.$2,
            restart: failed.$3,
            forward: failed.$4,
            backward: failed.$5,
          );
  }

  Future<void> next() {
    if (state.busy || state.nextCursor == null) return Future.value();
    return _load(state.nextCursor, state.page + 1, forward: true);
  }

  Future<void> previous() {
    if (state.busy || _previous.isEmpty) return Future.value();
    return _load(_previous.last, state.page - 1, backward: true);
  }

  Future<void> _load(
    String? cursor,
    int page, {
    bool restart = false,
    bool forward = false,
    bool backward = false,
  }) async {
    if (isClosed || state.blocked) return;
    _stop();
    final generation = _generation;
    final before = state;
    _failed = null;
    final cancel = _cancel = Completer<void>();
    emit(
      InvoiceFilterValuesState(
        query: before.query,
        items: before.items,
        nextCursor: before.nextCursor,
        loading: true,
        loaded: before.loaded,
        page: before.page,
        hasPrevious: _previous.isNotEmpty,
      ),
    );
    try {
      final result = await _repository.filterValues(
        field: field,
        query: before.query,
        limit: 20,
        cursor: cursor,
        cancel: cancel.future,
      );
      if (isClosed || generation != _generation) return;
      if (restart) _previous.clear();
      if (forward) {
        _previous.add(_cursor);
        if (_previous.length > 50) _previous.removeAt(0);
      }
      if (backward) _previous.removeLast();
      _cursor = cursor;
      emit(
        InvoiceFilterValuesState(
          query: before.query,
          items: result.items,
          nextCursor: result.nextCursor,
          loaded: true,
          page: page,
          hasPrevious: _previous.isNotEmpty,
        ),
      );
    } on InvoiceFailure catch (failure) {
      if (!isClosed && generation == _generation) {
        _failed = (cursor, page, restart, forward, backward);
        emit(
          InvoiceFilterValuesState(
            query: before.query,
            items: before.items,
            nextCursor: before.nextCursor,
            loaded: before.loaded,
            page: before.page,
            hasPrevious: _previous.isNotEmpty,
            error: failure.code == 'cancelled'
                ? null
                : 'Filter values could not be loaded. Please try again.',
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    _stop();
    return super.close();
  }
}
