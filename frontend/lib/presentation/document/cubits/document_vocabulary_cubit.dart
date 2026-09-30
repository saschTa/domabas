import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/document/interfaces/document_vocabulary_repository.dart';
import '../../../domain/document/models/document_failure.dart';
import '../../../domain/document/models/document_search.dart';
import '../../../domain/document/models/document_upload_validation.dart';
import '../../../domain/document/models/document_vocabulary.dart';

final class DocumentVocabularyViewport {
  const DocumentVocabularyViewport({required this.firstVisibleIndex});
  final int firstVisibleIndex;
}

final class DocumentVocabularyState {
  DocumentVocabularyState({
    this.field = DocumentVocabularyField.tag,
    this.rawQuery = '',
    this.composing = false,
    this.validation,
    Iterable<DocumentVocabularyOption> items = const [],
    this.nextCursor,
    this.loading = false,
    this.debouncing = false,
    this.loaded = false,
    this.error,
    this.released = false,
    this.admissionBlocked = false,
    this.resetRevision = 0,
  }) : items = List.unmodifiable(items);
  final DocumentVocabularyField field;
  final String rawQuery;
  final bool composing, loading, debouncing, loaded, released, admissionBlocked;
  final String? validation, nextCursor, error;
  final List<DocumentVocabularyOption> items;
  final int resetRevision;
  bool get blocked => composing || validation != null;
  DocumentVocabularyState copyWith({
    DocumentVocabularyField? field,
    String? rawQuery,
    bool? composing,
    String? validation,
    bool clearValidation = false,
    Iterable<DocumentVocabularyOption>? items,
    String? nextCursor,
    bool clearNext = false,
    bool? loading,
    bool? debouncing,
    bool? loaded,
    String? error,
    bool clearError = false,
    bool? released,
    bool? admissionBlocked,
    int? resetRevision,
  }) => DocumentVocabularyState(
    field: field ?? this.field,
    rawQuery: rawQuery ?? this.rawQuery,
    composing: composing ?? this.composing,
    validation: clearValidation ? null : validation ?? this.validation,
    items: items ?? this.items,
    nextCursor: clearNext ? null : nextCursor ?? this.nextCursor,
    loading: loading ?? this.loading,
    debouncing: debouncing ?? this.debouncing,
    loaded: loaded ?? this.loaded,
    error: clearError ? null : error ?? this.error,
    released: released ?? this.released,
    admissionBlocked: admissionBlocked ?? this.admissionBlocked,
    resetRevision: resetRevision ?? this.resetRevision,
  );
}

final class DocumentVocabularyCubit extends Cubit<DocumentVocabularyState> {
  DocumentVocabularyCubit(this._repository) : super(DocumentVocabularyState());
  final DocumentVocabularyRepository _repository;
  DocumentVocabularyViewport Function()? viewport;
  void Function(int removed)? beforeRelease;
  final _pages = <List<DocumentVocabularyOption>>[];
  final _pageCursors = <String?>[];
  int _generation = 0;
  Completer<void>? _request;
  Timer? _timer;
  bool _nearEnd = false, _leftBlockedThreshold = false;
  String? _failedCursor;
  bool _hasFailure = false;
  static const pageSize = 40, retainedLimit = 400;

  void _cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    if (_request case final request? when !request.isCompleted) {
      request.complete();
    }
    _request = null;
    _hasFailure = false;
    _failedCursor = null;
  }

  void _reset({DocumentVocabularyField? field, String? raw, bool? composing}) {
    _cancel();
    _pages.clear();
    _pageCursors.clear();
    _nearEnd = false;
    _leftBlockedThreshold = false;
    final query = raw ?? state.rawQuery;
    emit(
      DocumentVocabularyState(
        field: field ?? state.field,
        rawQuery: query,
        composing: composing ?? state.composing,
        validation: DocumentSearchCriteria.validateAddress(query),
        resetRevision: state.resetRevision + 1,
      ),
    );
  }

  Future<void> selectField(DocumentVocabularyField field) async {
    if (isClosed || field == state.field) return;
    _reset(field: field, raw: '', composing: false);
    await _load();
  }

  void editQuery(String raw, {required bool composing}) {
    if (isClosed || raw == state.rawQuery && composing == state.composing) {
      return;
    }
    _reset(raw: raw, composing: composing);
    if (state.blocked) return;
    final generation = _generation;
    emit(state.copyWith(debouncing: true));
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (isClosed || generation != _generation) return;
      _timer = null;
      emit(state.copyWith(debouncing: false));
      unawaited(_load());
    });
  }

  Future<void> submit() {
    _timer?.cancel();
    _timer = null;
    if (!isClosed && state.debouncing) emit(state.copyWith(debouncing: false));
    if (state.loaded) return restart();
    return _load();
  }

  Future<void> restart() {
    if (isClosed) return Future.value();
    _reset();
    return _load();
  }

  void setNearEnd(bool value) {
    if (isClosed) return;
    if (!value && state.admissionBlocked) _leftBlockedThreshold = true;
    final entered = value && !_nearEnd;
    _nearEnd = value;
    if (entered && state.admissionBlocked && _leftBlockedThreshold) {
      _leftBlockedThreshold = false;
      emit(state.copyWith(admissionBlocked: false, clearError: true));
    }
    if (value) unawaited(next());
  }

  Future<void> next() {
    if (!state.loaded ||
        state.nextCursor == null ||
        state.error != null ||
        state.admissionBlocked) {
      return Future.value();
    }
    return _load(cursor: state.nextCursor);
  }

  Future<void> retry() {
    if (isClosed) return Future.value();
    if (state.admissionBlocked) {
      emit(state.copyWith(admissionBlocked: false, clearError: true));
      return _load(cursor: state.nextCursor);
    }
    if (!_hasFailure) return Future.value();
    return _load(cursor: _failedCursor);
  }

  Future<void> _load({String? cursor}) async {
    if (isClosed || state.loading || state.blocked || state.debouncing) return;
    final generation = _generation;
    final cancel = _request = Completer<void>();
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final page = await _repository.lookup(
        state.field,
        query: DocumentUploadValidation.trim(state.rawQuery),
        limit: pageSize,
        cursor: cursor,
        cancel: cancel.future,
      );
      if (isClosed || generation != _generation) return;
      final retained = state.items.map((item) => item.key).toSet();
      final incoming = <DocumentVocabularyOption>[];
      final keys = <String>{};
      for (final item in page.items) {
        if (keys.add(item.key) && !retained.contains(item.key)) {
          incoming.add(item);
        }
      }
      if (page.items.length > pageSize ||
          page.nextCursor != null &&
              (page.nextCursor == cursor ||
                  _pageCursors.contains(page.nextCursor) ||
                  incoming.isEmpty)) {
        throw const DocumentFailure(DocumentFailureKind.invalidResponse);
      }
      var removed = 0, segments = 0;
      final firstVisible = viewport?.call().firstVisibleIndex ?? 0;
      while (state.items.length - removed + incoming.length > retainedLimit &&
          segments < _pages.length) {
        final count = _pages[segments].length;
        if (removed + count > firstVisible) break;
        removed += count;
        segments++;
      }
      if (state.items.length - removed + incoming.length > retainedLimit) {
        _leftBlockedThreshold = !_nearEnd;
        emit(
          state.copyWith(
            loading: false,
            admissionBlocked: true,
            error: 'Earlier options are visible. Scroll forward or retry.',
          ),
        );
        return;
      }
      if (removed > 0) {
        beforeRelease?.call(removed);
        _pages.removeRange(0, segments);
        _pageCursors.removeRange(0, segments);
      }
      if (incoming.isNotEmpty) {
        _pages.add(incoming);
        _pageCursors.add(cursor);
      }
      _hasFailure = false;
      _failedCursor = null;
      emit(
        state.copyWith(
          items: _pages.expand((page) => page),
          nextCursor: page.nextCursor,
          clearNext: page.nextCursor == null,
          loading: false,
          loaded: true,
          clearError: true,
          released: state.released || removed > 0,
        ),
      );
    } on DocumentFailure catch (failure) {
      if (!isClosed && generation == _generation) {
        _hasFailure = true;
        _failedCursor = cursor;
        emit(state.copyWith(loading: false, error: failure.message));
      }
    } finally {
      if (identical(cancel, _request)) _request = null;
    }
  }

  @override
  Future<void> close() async {
    _cancel();
    viewport = null;
    beforeRelease = null;
    await super.close();
  }
}
