import 'dart:async';
import 'dart:math' as math;

import 'package:bloc/bloc.dart';

import '../../../domain/invoice/interfaces/invoice_repository.dart';
import '../../../domain/invoice/models/invoice.dart';
import '../../../domain/invoice/models/invoice_search.dart';
import 'invoice_filter_values_cubit.dart';

final class InvoiceCriteria {
  const InvoiceCriteria({
    this.source,
    this.query = '',
    this.sort = InvoiceSort.automatic,
    this.filters = const InvoiceFilters(),
  });
  final String? source;
  final String query;
  final InvoiceSort sort;
  final InvoiceFilters filters;

  InvoiceCriteria copyWith({
    String? source,
    bool clearSource = false,
    String? query,
    InvoiceSort? sort,
    InvoiceFilters? filters,
  }) => InvoiceCriteria(
    source: clearSource ? null : source ?? this.source,
    query: query ?? this.query,
    sort: sort ?? this.sort,
    filters: filters ?? this.filters,
  );

  bool matches(InvoiceCriteria? other) =>
      other != null &&
      source == other.source &&
      query == other.query &&
      sort == other.sort &&
      filters.matches(other.filters);
}

final class InvoicesState {
  InvoicesState({
    Iterable<Invoice> items = const [],
    this.criteria = const InvoiceCriteria(),
    this.snapshot,
    this.cursor,
    this.loading = false,
    this.browsingHistory = false,
    this.rawTerm = '',
    this.composing = false,
    this.debouncing = false,
    this.termError,
    this.snapshotVersion = 0,
    this.error,
  }) : items = List.unmodifiable(items);

  final List<Invoice> items;
  final InvoiceCriteria criteria;
  final InvoiceCriteria? snapshot;
  final String? cursor, error, termError;
  final String rawTerm;
  final bool loading, browsingHistory, composing, debouncing;
  final int snapshotVersion;
  String? get source => criteria.source;
  bool get loaded => snapshot != null;
  bool get intentBlocked => composing || termError != null;
  bool get matchesSnapshot => criteria.matches(snapshot);
  bool get canPaginate =>
      matchesSnapshot && !loading && !debouncing && !intentBlocked;
  String get status => composing
      ? 'Finish entering the search'
      : termError != null
      ? 'Check the search text'
      : debouncing
      ? 'Waiting for search…'
      : loading
      ? loaded
            ? 'Updating invoices…'
            : 'Loading invoices…'
      : error != null
      ? 'Could not update invoices'
      : '${items.length} ${items.length == 1 ? 'invoice' : 'invoices'} loaded';

  InvoicesState copyWith({
    Iterable<Invoice>? items,
    InvoiceCriteria? criteria,
    InvoiceCriteria? snapshot,
    String? cursor,
    bool clearCursor = false,
    bool? loading,
    bool? browsingHistory,
    String? rawTerm,
    bool? composing,
    bool? debouncing,
    String? termError,
    bool clearTermError = false,
    int? snapshotVersion,
    String? error,
    bool clearError = false,
  }) => InvoicesState(
    items: items ?? this.items,
    criteria: criteria ?? this.criteria,
    snapshot: snapshot ?? this.snapshot,
    cursor: clearCursor ? null : cursor ?? this.cursor,
    loading: loading ?? this.loading,
    browsingHistory: browsingHistory ?? this.browsingHistory,
    rawTerm: rawTerm ?? this.rawTerm,
    composing: composing ?? this.composing,
    debouncing: debouncing ?? this.debouncing,
    termError: clearTermError ? null : termError ?? this.termError,
    snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    error: clearError ? null : error ?? this.error,
  );
}

final class InvoicesCubit extends Cubit<InvoicesState> {
  InvoicesCubit(this._repository, {required bool allowed})
    : allowed = allowed && _repository != null,
      super(InvoicesState());

  final InvoiceRepository? _repository;
  final bool allowed;
  bool _active = false, _reading = false, _background = false;
  int _epoch = 0;
  Completer<void>? _cancel;
  Timer? _timer, _debounce;

  InvoiceDetailCubit details(String id, {Invoice? initial}) =>
      InvoiceDetailCubit(_repository!, id, initial: initial);

  InvoiceFilterValuesCubit filterValues(InvoiceFilterField field) =>
      InvoiceFilterValuesCubit(_repository!, field);

  void setActive(bool active) {
    if (isClosed || !allowed || _active == active) return;
    _active = active;
    _stop();
    emit(state.copyWith(loading: false, debouncing: false));
    if (active) unawaited(load(background: true));
  }

  void editTerm(String raw, {required bool composing}) {
    if (isClosed ||
        !allowed ||
        (raw == state.rawTerm && composing == state.composing)) {
      return;
    }
    _stop();
    final query = raw.trim();
    final error = query.runes.length > 200
        ? 'Use 200 characters or fewer.'
        : null;
    final debouncing = _active && !composing && error == null;
    emit(
      state.copyWith(
        criteria: state.criteria.copyWith(query: query),
        rawTerm: raw,
        composing: composing,
        termError: error,
        clearTermError: error == null,
        loading: false,
        debouncing: debouncing,
        clearError: true,
      ),
    );
    if (debouncing) {
      final epoch = _epoch;
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (isClosed || epoch != _epoch) return;
        _debounce = null;
        unawaited(load());
      });
    }
  }

  Future<void> submitSearch() => load();

  Future<void> clearSearch() {
    if (isClosed || !allowed) return Future.value();
    editTerm('', composing: false);
    return load();
  }

  void filter(String? source) {
    if (isClosed || !allowed || source == state.source) return;
    if (source != null && source != 'structured' && source != 'ai') return;
    _stop();
    emit(
      state.copyWith(
        criteria: state.criteria.copyWith(
          source: source,
          clearSource: source == null,
        ),
        loading: false,
        debouncing: false,
        clearError: true,
      ),
    );
    unawaited(load());
  }

  Future<void> setSort(InvoiceSort sort) =>
      _setCriteria(state.criteria.copyWith(sort: sort));

  Future<void> setFilters(InvoiceFilters filters) {
    if (filters.validation != null) return Future.value();
    return _setCriteria(state.criteria.copyWith(filters: filters));
  }

  Future<void> clearFilters() => setFilters(const InvoiceFilters());

  Future<void> _setCriteria(InvoiceCriteria criteria) {
    if (isClosed || !allowed || criteria.matches(state.criteria)) {
      return Future.value();
    }
    _stop();
    emit(
      state.copyWith(
        criteria: criteria,
        loading: false,
        debouncing: false,
        clearError: true,
      ),
    );
    return load();
  }

  void invalidate() {
    if (_active && !_reading) unawaited(load(background: true));
  }

  void _stop() {
    _epoch++;
    _timer?.cancel();
    _debounce?.cancel();
    _debounce = null;
    if (_cancel case final cancel? when !cancel.isCompleted) cancel.complete();
    _reading = false;
  }

  Future<void> load({bool background = false, bool more = false}) async {
    if (isClosed || !allowed || !_active || state.intentBlocked) return;
    if (background && state.debouncing) return;
    if (more && (!state.canPaginate || state.cursor == null)) return;
    if (!background && _reading && _background) _stop();
    if (_reading) return;
    _debounce?.cancel();
    _debounce = null;
    background = background && state.matchesSnapshot;
    final previous = state;
    final epoch = ++_epoch;
    final cancel = _cancel = Completer<void>();
    _reading = true;
    _background = background;
    _timer?.cancel();
    emit(
      previous.copyWith(
        loading: !background,
        debouncing: false,
        clearError: !background,
      ),
    );
    bool current() => !isClosed && _active && epoch == _epoch;
    try {
      final windowSize = background && !more && previous.browsingHistory
          ? math.max(20, previous.items.length)
          : 20;
      final pageCount = (windowSize + 19) ~/ 20;
      final refreshed = <String, Invoice>{};
      var cursor = more ? previous.cursor : null;
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        final page = await _repository!.list(
          limit: (windowSize - pageIndex * 20).clamp(1, 20),
          cursor: cursor,
          source: previous.source,
          query: previous.criteria.query,
          sort: previous.criteria.sort,
          filters: previous.criteria.filters,
          cancel: cancel.future,
        );
        if (!current()) return;
        for (final invoice in page.items) {
          refreshed[invoice.id] = invoice;
        }
        cursor = page.nextCursor;
        if (cursor == null) break;
      }
      var items = refreshed.values.toList();
      if (more) {
        final ids = previous.items.map((invoice) => invoice.id).toSet();
        items = [
          ...previous.items,
          ...items.where((invoice) => ids.add(invoice.id)),
        ];
      }
      emit(
        previous.copyWith(
          items: items,
          snapshot: previous.criteria,
          snapshotVersion:
              previous.snapshotVersion + (previous.matchesSnapshot ? 0 : 1),
          cursor: cursor,
          clearCursor: cursor == null,
          loading: false,
          debouncing: false,
          browsingHistory: more || (background && previous.browsingHistory),
          clearError: true,
        ),
      );
    } on InvoiceFailure catch (failure) {
      if (current()) {
        emit(
          previous.copyWith(
            loading: false,
            debouncing: false,
            error: failure.code == 'cancelled' ? null : failure.message,
          ),
        );
      }
    } finally {
      if (current()) {
        _reading = false;
        _timer = Timer(
          Duration(seconds: state.error == null ? 15 : 30),
          () => unawaited(load(background: true)),
        );
      }
    }
  }

  @override
  Future<void> close() {
    _active = false;
    _stop();
    return super.close();
  }
}

final class InvoiceDetailState {
  const InvoiceDetailState({this.invoice, this.loading = false, this.error});
  final Invoice? invoice;
  final bool loading;
  final String? error;
}

final class InvoiceDetailCubit extends Cubit<InvoiceDetailState> {
  InvoiceDetailCubit(this._repository, this.id, {Invoice? initial})
    : super(InvoiceDetailState(invoice: initial));

  final InvoiceRepository _repository;
  final String id;
  final _cancel = Completer<void>();

  InvoiceDetailCubit reference(String id) =>
      InvoiceDetailCubit(_repository, id);

  Future<void> load() async {
    if (isClosed || state.loading) return;
    emit(InvoiceDetailState(invoice: state.invoice, loading: true));
    try {
      final invoice = await _repository.get(id, cancel: _cancel.future);
      if (!isClosed) emit(InvoiceDetailState(invoice: invoice));
    } on InvoiceFailure catch (failure) {
      if (!isClosed && failure.code != 'cancelled') {
        emit(
          InvoiceDetailState(invoice: state.invoice, error: failure.message),
        );
      }
    }
  }

  @override
  Future<void> close() {
    if (!_cancel.isCompleted) _cancel.complete();
    return super.close();
  }
}
