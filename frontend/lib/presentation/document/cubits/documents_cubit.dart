import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_capabilities.dart';
import '../../../domain/document/models/document_failure.dart';
import '../../../domain/document/models/document_search.dart';
import '../../../domain/document/models/document_vocabulary.dart';
import '../../../domain/document/interfaces/document_repository.dart';
import '../../../domain/document/interfaces/document_file_saver.dart';
import '../models/document_previews.dart';
import 'document_cubit.dart';
import 'document_email_links_cubit.dart';

enum DocumentLayout { grid, list }

final class DocumentSearchPosition {
  const DocumentSearchPosition(this.cursor, this.ordinal);
  final String? cursor;
  final int ordinal;
}

final class DocumentSearchRequest {
  DocumentSearchRequest({
    required this.criteria,
    this.cursor,
    this.ordinal = 1,
    Iterable<DocumentSearchPosition> history = const [],
    this.notice,
  }) : history = List.unmodifiable(history);
  final DocumentSearchCriteria criteria;
  final String? cursor;
  final int ordinal;
  final List<DocumentSearchPosition> history;
  final String? notice;
}

final class DocumentsState {
  DocumentsState({
    Iterable<Document> documents = const [],
    Iterable<DocumentSearchResult> results = const [],
    this.criteria,
    DocumentSearchCriteria? desiredCriteria,
    this.searchRequest,
    this.failedRequest,
    this.nextCursor,
    this.total = 0,
    this.totalKnown = true,
    this.page = 0,
    this.layout = DocumentLayout.grid,
    this.isLoading = false,
    this.backgroundLoading = false,
    this.isSaving = false,
    this.hasSnapshot = false,
    this.rawTerm = '',
    this.composing = false,
    this.termError,
    this.debouncing = false,
    this.intentRevision = 0,
    this.error,
    this.saveError,
    this.notice,
    this.previewEpoch = 0,
    this.scrollEpoch = 0,
    this.upToDate = false,
    this.confirmedMutation = false,
    Iterable<DocumentVocabularyOption> selectedTags = const [],
    this.selectedSender,
    this.selectedRecipient,
  }) : documents = List.unmodifiable(documents),
       results = List.unmodifiable(results),
       desiredCriteria =
           desiredCriteria ?? criteria ?? DocumentSearchCriteria(),
       selectedTags = List.unmodifiable(selectedTags);
  final List<Document> documents;
  final List<DocumentSearchResult> results;
  final DocumentSearchCriteria? criteria;
  final DocumentSearchCriteria desiredCriteria;
  final DocumentSearchRequest? searchRequest;
  final DocumentSearchRequest? failedRequest;
  final String? nextCursor;
  final int total, page, intentRevision;
  final bool totalKnown;
  final DocumentLayout layout;
  final bool isLoading, isSaving, hasSnapshot, composing, debouncing, upToDate;
  final bool backgroundLoading;
  bool get showLoading => isLoading && !backgroundLoading;
  final bool confirmedMutation;
  final String rawTerm;
  final String? termError, error, saveError, notice;
  final int previewEpoch, scrollEpoch;
  final List<DocumentVocabularyOption> selectedTags;
  final DocumentVocabularyOption? selectedSender, selectedRecipient;
  bool get searching => criteria != null;
  bool get intentBlocked => composing || termError != null;
  bool get desiredSearching =>
      desiredCriteria.query.isNotEmpty ||
      desiredCriteria.filterCount > 0 ||
      desiredCriteria.sort != DocumentSort.newest;
  bool get desiredMatchesSnapshot =>
      hasSnapshot &&
      (desiredSearching
          ? desiredCriteria.identity == criteria?.identity
          : criteria == null);
  bool get canPaginate =>
      desiredMatchesSnapshot &&
      !showLoading &&
      !debouncing &&
      !intentBlocked &&
      !isSaving;
  String get status => composing
      ? confirmedMutation
            ? 'Change saved. Finish entering search'
            : 'Finish entering the search'
      : termError != null
      ? confirmedMutation
            ? 'Change saved. Check the search text'
            : 'Check the search text'
      : debouncing
      ? 'Waiting for search…'
      : isLoading
      ? confirmedMutation
            ? 'Change saved. Updating documents…'
            : (hasSnapshot
                  ? 'Updating… Previous results remain visible'
                  : 'Loading documents…')
      : error != null
      ? confirmedMutation
            ? 'Change saved. Could not update documents'
            : 'Could not update documents'
      : upToDate
      ? 'Up to date'
      : confirmedMutation
      ? 'Change saved. Collection update is pending'
      : 'Documents have not been updated';
  int get ordinal => searchRequest?.ordinal ?? 1;
  int get pages => (total / DocumentsCubit.pageSize).ceil().clamp(1, 1 << 30);
  DocumentsState copyWith({
    Iterable<Document>? documents,
    Iterable<DocumentSearchResult>? results,
    DocumentSearchCriteria? criteria,
    DocumentSearchCriteria? desiredCriteria,
    DocumentSearchRequest? searchRequest,
    DocumentSearchRequest? failedRequest,
    String? nextCursor,
    bool clearSearch = false,
    bool clearFailed = false,
    bool clearNext = false,
    int? total,
    bool? totalKnown,
    int? page,
    DocumentLayout? layout,
    bool? isLoading,
    bool? backgroundLoading,
    bool? isSaving,
    bool? hasSnapshot,
    String? rawTerm,
    bool? composing,
    String? termError,
    bool clearTermError = false,
    bool? debouncing,
    int? intentRevision,
    bool? upToDate,
    bool? confirmedMutation,
    String? error,
    String? saveError,
    String? notice,
    bool clearError = false,
    bool clearSaveError = false,
    bool clearNotice = false,
    int? previewEpoch,
    int? scrollEpoch,
    Iterable<DocumentVocabularyOption>? selectedTags,
    DocumentVocabularyOption? selectedSender,
    DocumentVocabularyOption? selectedRecipient,
    bool clearSender = false,
    bool clearRecipient = false,
  }) => DocumentsState(
    documents: documents ?? this.documents,
    results: clearSearch ? const [] : results ?? this.results,
    criteria: clearSearch ? null : criteria ?? this.criteria,
    desiredCriteria: desiredCriteria ?? this.desiredCriteria,
    searchRequest: clearSearch ? null : searchRequest ?? this.searchRequest,
    failedRequest: clearFailed ? null : failedRequest ?? this.failedRequest,
    nextCursor: clearSearch || clearNext ? null : nextCursor ?? this.nextCursor,
    total: total ?? this.total,
    totalKnown: totalKnown ?? this.totalKnown,
    page: page ?? this.page,
    layout: layout ?? this.layout,
    isLoading: isLoading ?? this.isLoading,
    backgroundLoading: backgroundLoading ?? this.backgroundLoading,
    isSaving: isSaving ?? this.isSaving,
    hasSnapshot: hasSnapshot ?? this.hasSnapshot,
    rawTerm: rawTerm ?? this.rawTerm,
    composing: composing ?? this.composing,
    termError: clearTermError ? null : termError ?? this.termError,
    debouncing: debouncing ?? this.debouncing,
    intentRevision: intentRevision ?? this.intentRevision,
    upToDate: upToDate ?? this.upToDate,
    confirmedMutation: confirmedMutation ?? this.confirmedMutation,
    error: clearError ? null : error ?? this.error,
    saveError: clearSaveError ? null : saveError ?? this.saveError,
    notice: clearNotice ? null : notice ?? this.notice,
    previewEpoch: previewEpoch ?? this.previewEpoch,
    scrollEpoch: scrollEpoch ?? this.scrollEpoch,
    selectedTags: selectedTags ?? this.selectedTags,
    selectedSender: clearSender ? null : selectedSender ?? this.selectedSender,
    selectedRecipient: clearRecipient
        ? null
        : selectedRecipient ?? this.selectedRecipient,
  );
}

final class DocumentsCubit extends Cubit<DocumentsState> {
  DocumentsCubit(
    this._repository, {
    this.capabilities = const DocumentCapabilities(),
    this.fileSaver,
  }) : previews = DocumentPreviewCoordinator(_repository),
       super(DocumentsState());
  final DocumentRepository _repository;
  final DocumentCapabilities capabilities;
  final DocumentFileSaver? fileSaver;
  final DocumentPreviewCoordinator previews;
  final _viewers = <DocumentCubit>{};
  final _viewerLinks = <DocumentCubit, DocumentEmailLinksCubit>{};
  final _visibleViewers = <DocumentCubit>{};
  bool _foreground = false, _collectionVisible = true, _previewsActive = true;
  late final _refresh = AutomaticRefresh(
    read: () => _coveredInvalidation < _invalidation
        ? _readDesired(automatic: true)
        : Future.value(),
    busy: () => false,
    interval: () => Duration(seconds: state.error == null ? 1 : 30),
  );
  static const pageSize = 48;
  int _generation = 0, _invalidation = 0, _coveredInvalidation = 0;
  Completer<void>? _collection;
  Timer? _debounce;
  String? _activeKey;
  Future<void>? _activeRead;
  int? _failedBrowse, _failedRevision;
  bool _closing = false, _uncertainCreate = false;
  List<Document> get documents => state.documents;
  int get total => state.total;
  bool get isLoading => state.isLoading;
  bool get isSaving => state.isSaving;
  bool get canLoadMore =>
      state.canPaginate &&
      (state.searching
          ? state.nextCursor != null
          : state.page + 1 < state.pages);
  String? get error => state.error;
  String? get saveError => state.saveError;

  void setActive(bool foreground, {bool collectionVisible = true}) {
    _foreground = foreground;
    _collectionVisible = collectionVisible;
    _syncRefresh();
  }

  void invalidate() {
    if (_closing) return;
    _markInvalid();
    for (final viewer in _viewers) {
      viewer.invalidate();
      _viewerLinks[viewer]?.invalidate();
    }
  }

  void _markInvalid() {
    _invalidation++;
    emit(state.copyWith(upToDate: false));
    _refresh.invalidate();
    _syncRefresh();
  }

  void attachLinks(DocumentCubit viewer, DocumentEmailLinksCubit links) {
    if (!_viewers.contains(viewer) || _closing) return;
    _viewerLinks[viewer] = links;
    _syncRefresh();
  }

  void setViewerActive(DocumentCubit viewer, bool active) {
    if (!_viewers.contains(viewer) || _closing) return;
    active ? _visibleViewers.add(viewer) : _visibleViewers.remove(viewer);
    _syncRefresh();
  }

  void _syncRefresh() {
    if (_closing) return;
    final collection = _foreground && _collectionVisible && _viewers.isEmpty;
    _refresh.setActive(
      collection &&
          !state.intentBlocked &&
          !state.debouncing &&
          !state.isLoading &&
          !state.isSaving,
    );
    if (_previewsActive != collection) {
      _previewsActive = collection;
      if (collection) {
        previews.resume();
        emit(state.copyWith(previewEpoch: state.previewEpoch + 1));
      } else {
        previews.pause();
      }
    }
    for (final viewer in _viewers) {
      final active = _foreground && _visibleViewers.contains(viewer);
      viewer.setActive(active);
      _viewerLinks[viewer]?.setActive(active);
    }
  }

  void setLayout(DocumentLayout layout) {
    if (!_closing) emit(state.copyWith(layout: layout));
  }

  void _cancelRead() {
    _generation++;
    final previous = _collection;
    if (previous != null && !previous.isCompleted) previous.complete();
    _collection = null;
    _activeKey = null;
    _activeRead = null;
  }

  void _fence() {
    _debounce?.cancel();
    _debounce = null;
    _cancelRead();
    _failedBrowse = null;
    _failedRevision = null;
    emit(
      state.copyWith(
        intentRevision: state.intentRevision + 1,
        isLoading: false,
        backgroundLoading: false,
        debouncing: false,
        clearFailed: true,
        clearError: true,
        clearNotice: true,
        upToDate: false,
      ),
    );
  }

  void editTerm(String raw, {required bool composing}) {
    if (_closing ||
        !capabilities.search ||
        !capabilities.read ||
        raw == state.rawTerm && composing == state.composing) {
      return;
    }
    _fence();
    final error = DocumentSearchCriteria.validateTerm(raw);
    emit(
      state.copyWith(
        rawTerm: raw,
        composing: composing,
        termError: error,
        clearTermError: error == null,
        desiredCriteria: error == null
            ? state.desiredCriteria.copyWith(query: raw)
            : null,
      ),
    );
    if (!state.intentBlocked) {
      final revision = state.intentRevision;
      emit(state.copyWith(debouncing: true));
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (_closing || revision != state.intentRevision) return;
        _debounce = null;
        emit(state.copyWith(debouncing: false));
        unawaited(_readDesired(first: true));
      });
    }
    _syncRefresh();
  }

  Future<void> submitSearch() {
    _debounce?.cancel();
    _debounce = null;
    if (!_closing && state.debouncing) emit(state.copyWith(debouncing: false));
    return _readDesired(first: true);
  }

  Future<void> applySearch(DocumentSearchCriteria criteria) async {
    if (_closing || !capabilities.read || !capabilities.search) return;
    _fence();
    final error = DocumentSearchCriteria.validateTerm(criteria.query);
    emit(
      state.copyWith(
        desiredCriteria: criteria,
        rawTerm: criteria.query,
        composing: false,
        termError: error,
        clearTermError: error == null,
        selectedTags: state.selectedTags.where(
          (option) => criteria.tags.contains(option.value),
        ),
        clearSender:
            criteria.senderMatch != DocumentAddressMatch.exact ||
            state.selectedSender?.value != criteria.sender,
        clearRecipient:
            criteria.recipientMatch != DocumentAddressMatch.exact ||
            state.selectedRecipient?.value != criteria.recipient,
      ),
    );
    await _readDesired(first: true);
  }

  Future<void> _changeCriteria(
    DocumentSearchCriteria criteria, {
    Iterable<DocumentVocabularyOption>? tags,
    DocumentVocabularyOption? sender,
    DocumentVocabularyOption? recipient,
    bool clearSender = false,
    bool clearRecipient = false,
  }) async {
    if (_closing || !capabilities.read || !capabilities.search) return;
    _fence();
    emit(
      state.copyWith(
        desiredCriteria: criteria,
        selectedTags: tags,
        selectedSender: sender,
        selectedRecipient: recipient,
        clearSender: clearSender,
        clearRecipient: clearRecipient,
      ),
    );
    await _readDesired(first: true);
  }

  Future<void> setSort(DocumentSort sort) =>
      _changeCriteria(state.desiredCriteria.copyWith(sort: sort));
  Future<void> setKinds(Iterable<DocumentKind> kinds) =>
      _changeCriteria(state.desiredCriteria.copyWith(kinds: kinds));
  Future<void> clearKinds() => setKinds(const []);
  Future<void> selectOption(
    DocumentVocabularyField field,
    DocumentVocabularyOption option,
  ) {
    final criteria = state.desiredCriteria;
    switch (field) {
      case DocumentVocabularyField.tag:
        final selected = [...state.selectedTags];
        final existing = selected.indexWhere((item) => item.key == option.key);
        if (existing >= 0) {
          final removed = selected.removeAt(existing);
          return _changeCriteria(
            criteria.copyWith(
              tags: criteria.tags.where((value) => value != removed.value),
              canonicalTags: true,
            ),
            tags: selected,
          );
        }
        if (criteria.tags.length >= 20) return Future.value();
        selected.add(option);
        return _changeCriteria(
          criteria.copyWith(
            tags: {...criteria.tags, option.value},
            canonicalTags: true,
          ),
          tags: selected,
        );
      case DocumentVocabularyField.sender:
        return _changeCriteria(
          criteria.copyWith(
            sender: option.value,
            senderMatch: DocumentAddressMatch.exact,
          ),
          sender: option,
        );
      case DocumentVocabularyField.recipient:
        return _changeCriteria(
          criteria.copyWith(
            recipient: option.value,
            recipientMatch: DocumentAddressMatch.exact,
          ),
          recipient: option,
        );
    }
  }

  Future<void> removeTag(String value) => _changeCriteria(
    state.desiredCriteria.copyWith(
      tags: state.desiredCriteria.tags.where((tag) => tag != value),
    ),
    tags: state.selectedTags.where((option) => option.value != value),
  );
  Future<void> clearAddress(DocumentVocabularyField field) =>
      field == DocumentVocabularyField.sender
      ? _changeCriteria(
          state.desiredCriteria.copyWith(
            sender: '',
            senderMatch: DocumentAddressMatch.contains,
          ),
          clearSender: true,
        )
      : _changeCriteria(
          state.desiredCriteria.copyWith(
            recipient: '',
            recipientMatch: DocumentAddressMatch.contains,
          ),
          clearRecipient: true,
        );
  Future<void> resetFilters() => _changeCriteria(
    state.desiredCriteria.copyWith(
      kinds: const [],
      tags: const [],
      sender: '',
      recipient: '',
      senderMatch: DocumentAddressMatch.contains,
      recipientMatch: DocumentAddressMatch.contains,
    ),
    tags: const [],
    clearSender: true,
    clearRecipient: true,
  );

  Future<void> load({bool more = false, int? page, bool automatic = false}) {
    if (_closing) return Future.value();
    _debounce?.cancel();
    _debounce = null;
    if (state.debouncing) emit(state.copyWith(debouncing: false));
    if (more && state.searching) return nextSearchPage();
    return _readDesired(
      browsePage: page ?? (more ? state.page + 1 : null),
      automatic: automatic,
    );
  }

  Future<void> _readDesired({
    bool first = false,
    int? browsePage,
    bool automatic = false,
  }) {
    if (_closing ||
        !capabilities.read ||
        state.intentBlocked ||
        state.isSaving) {
      _syncRefresh();
      return Future.value();
    }
    if (state.desiredSearching) {
      if (!capabilities.search) return Future.value();
      final target =
          !first && state.desiredMatchesSnapshot && state.searchRequest != null
          ? state.searchRequest!
          : DocumentSearchRequest(criteria: state.desiredCriteria);
      return _read(target: target, automatic: automatic);
    }
    return _read(
      browsePage: first
          ? 0
          : browsePage ?? (state.desiredMatchesSnapshot ? state.page : 0),
      automatic: automatic,
    );
  }

  Future<void> _read({
    DocumentSearchRequest? target,
    int browsePage = 0,
    bool automatic = false,
  }) {
    if (_closing || state.intentBlocked || state.isSaving) {
      return Future.value();
    }
    final key =
        '${state.intentRevision}/${target?.criteria.identity ?? 'browse'}/${target?.cursor ?? browsePage}';
    if (_activeKey == key && _activeRead != null) {
      if (!automatic && state.backgroundLoading) {
        emit(state.copyWith(backgroundLoading: false));
      }
      return _activeRead!;
    }
    _cancelRead();
    _activeKey = key;
    final future = _performRead(
      target: target,
      browsePage: browsePage,
      automatic: automatic,
    );
    _activeRead = future;
    return future;
  }

  Future<void> _performRead({
    DocumentSearchRequest? target,
    required int browsePage,
    required bool automatic,
  }) async {
    final generation = _generation,
        intent = state.intentRevision,
        covered = _invalidation;
    final cancel = _collection = Completer<void>();
    emit(
      state.copyWith(
        isLoading: true,
        backgroundLoading: automatic && state.hasSnapshot,
        clearError: !automatic,
        clearFailed: !automatic,
        upToDate: false,
        clearNotice: !automatic,
      ),
    );
    _syncRefresh();
    bool current() =>
        !_closing &&
        generation == _generation &&
        intent == state.intentRevision;
    try {
      if (target != null) {
        var committed = target;
        var result = await _repository.search(
          target.criteria,
          limit: pageSize,
          cursor: target.cursor,
          cancel: cancel.future,
        );
        if (!current()) return;
        if (result.items.isEmpty && target.ordinal > 1) {
          committed = DocumentSearchRequest(
            criteria: target.criteria,
            notice: 'Results changed. Showing the first page.',
          );
          result = await _repository.search(
            target.criteria,
            limit: pageSize,
            cancel: cancel.future,
          );
        }
        if (!current()) return;
        final changed =
            state.criteria?.identity != committed.criteria.identity ||
            state.searchRequest?.cursor != committed.cursor;
        _coveredInvalidation = covered;
        emit(
          state.copyWith(
            results: result.items,
            documents: const [],
            total: result.total ?? 0,
            totalKnown: result.total != null,
            criteria: committed.criteria,
            searchRequest: committed,
            nextCursor: result.nextCursor,
            clearNext: result.nextCursor == null,
            clearFailed: true,
            isLoading: false,
            backgroundLoading: false,
            hasSnapshot: true,
            confirmedMutation:
                state.confirmedMutation && covered < _invalidation,
            clearError: true,
            notice: state.confirmedMutation && covered == _invalidation
                ? 'Results updated.'
                : committed.notice,
            upToDate: _coveredInvalidation == _invalidation,
            scrollEpoch: state.scrollEpoch + (changed ? 1 : 0),
          ),
        );
      } else {
        var actual = browsePage;
        var result = await _repository.list(
          limit: pageSize,
          offset: actual * pageSize,
          cancel: cancel.future,
        );
        if (!current()) return;
        if (result.items.isEmpty && actual > 0) {
          actual = ((result.total - 1).clamp(0, 1 << 30) ~/ pageSize);
          result = await _repository.list(
            limit: pageSize,
            offset: actual * pageSize,
            cancel: cancel.future,
          );
        }
        if (!current()) return;
        final changed = state.searching || actual != state.page;
        _coveredInvalidation = covered;
        emit(
          state.copyWith(
            documents: result.items,
            total: result.total,
            totalKnown: true,
            page: actual,
            clearSearch: true,
            clearFailed: true,
            isLoading: false,
            backgroundLoading: false,
            hasSnapshot: true,
            confirmedMutation:
                state.confirmedMutation && covered < _invalidation,
            clearError: true,
            notice: state.confirmedMutation && covered == _invalidation
                ? 'Results updated.'
                : null,
            upToDate: _coveredInvalidation == _invalidation,
            scrollEpoch: state.scrollEpoch + (changed ? 1 : 0),
          ),
        );
      }
      if (!automatic) _uncertainCreate = false;
      _failedBrowse = null;
      _failedRevision = null;
    } on DocumentFailure catch (failure) {
      if (current()) {
        _failedRevision = intent;
        _failedBrowse = target == null ? browsePage : null;
        emit(
          state.copyWith(
            isLoading: false,
            backgroundLoading: false,
            failedRequest: target,
            error: failure.message,
          ),
        );
      }
    } finally {
      if (current()) {
        _activeRead = null;
        _activeKey = null;
        _collection = null;
        _syncRefresh();
      }
    }
  }

  Future<void> retryCollection() {
    if (_closing ||
        state.intentBlocked ||
        _failedRevision != state.intentRevision) {
      return Future.value();
    }
    return _read(target: state.failedRequest, browsePage: _failedBrowse ?? 0);
  }

  Future<void> nextSearchPage() async {
    final current = state.searchRequest;
    if (!state.canPaginate || current == null || state.nextCursor == null) {
      return;
    }
    final history = [
      ...current.history,
      DocumentSearchPosition(current.cursor, current.ordinal),
    ];
    if (history.length > 50) history.removeAt(0);
    await _read(
      target: DocumentSearchRequest(
        criteria: current.criteria,
        cursor: state.nextCursor,
        ordinal: current.ordinal + 1,
        history: history,
      ),
    );
  }

  Future<void> previousSearchPage() async {
    final current = state.searchRequest;
    if (!state.canPaginate || current == null || current.history.isEmpty) {
      return;
    }
    final previous = current.history.last;
    await _read(
      target: DocumentSearchRequest(
        criteria: current.criteria,
        cursor: previous.cursor,
        ordinal: previous.ordinal,
        history: current.history.take(current.history.length - 1),
      ),
    );
  }

  Future<void> firstSearchPage() =>
      state.canPaginate ? _readDesired(first: true) : Future.value();
  Future<void> clearSearch() async {
    if (_closing) return;
    _fence();
    emit(
      state.copyWith(
        desiredCriteria: DocumentSearchCriteria(),
        rawTerm: '',
        composing: false,
        clearTermError: true,
        selectedTags: const [],
        clearSender: true,
        clearRecipient: true,
      ),
    );
    await _readDesired(first: true);
  }

  Future<void> _mutated({bool confirmed = true}) async {
    if (_closing) return;
    _markInvalid();
    if (confirmed) emit(state.copyWith(confirmedMutation: true));
    _debounce?.cancel();
    _debounce = null;
    if (state.debouncing) emit(state.copyWith(debouncing: false));
    await _readDesired(first: true);
    if (!_closing && state.upToDate) {
      emit(state.copyWith(notice: 'Results updated.'));
    }
  }

  Future<bool> create(DocumentDraft draft) async {
    if (_closing || state.isSaving || !capabilities.create) return false;
    if (_uncertainCreate) {
      await _mutated(confirmed: false);
      if (_closing) return false;
      emit(
        state.copyWith(
          saveError: 'Check the refreshed library before creating again. The earlier save may have completed.',
        ),
      );
      return false;
    }
    _cancelRead();
    _debounce?.cancel();
    _debounce = null;
    emit(
      state.copyWith(
        isSaving: true,
        isLoading: false,
        backgroundLoading: false,
        debouncing: false,
        clearSaveError: true,
      ),
    );
    _syncRefresh();
    try {
      await _repository.create(draft);
      if (_closing) return false;
      emit(state.copyWith(isSaving: false));
      await _mutated();
      return !_closing;
    } on DocumentFailure catch (failure) {
      _uncertainCreate =
          failure.kind == DocumentFailureKind.unavailable ||
          failure.kind == DocumentFailureKind.invalidResponse;
      if (!_closing) {
        emit(
          state.copyWith(
            isSaving: false,
            saveError: _uncertainCreate
                ? 'The save could not be confirmed. Refresh and check the library before trying again.'
                : failure.message,
          ),
        );
        _syncRefresh();
      }
      return false;
    }
  }

  void clearSaveError() {
    if (!_closing) emit(state.copyWith(clearSaveError: true));
  }

  Future<Document> getById(String id) => _repository.getById(id);
  DocumentEmailLinksCubit emailLinks(String id) =>
      DocumentEmailLinksCubit(_repository, id);
  DocumentCubit openDocument(String id) {
    final viewer = DocumentCubit(
      _repository,
      id: id,
      capabilities: capabilities,
      fileSaver: fileSaver,
      onUpdated: _replace,
      onMutation: _mutated,
      onDeleted: (id) async {
        previews.evict(id);
        for (final viewer
            in _viewers.where((value) => value.id == id).toList()) {
          await _viewerLinks.remove(viewer)?.close();
        }
      },
    );
    _viewers.add(viewer);
    _visibleViewers.add(viewer);
    _syncRefresh();
    return viewer;
  }

  Future<void> closeDocument(DocumentCubit viewer) async {
    _viewers.remove(viewer);
    _visibleViewers.remove(viewer);
    await _viewerLinks.remove(viewer)?.close();
    await viewer.close();
    _syncRefresh();
  }

  void _replace(Document document) {
    if (_closing || state.searching) return;
    emit(
      state.copyWith(
        documents: state.documents.map(
          (item) => item.id == document.id ? document : item,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _debounce?.cancel();
    _refresh.dispose();
    _cancelRead();
    previews.close();
    _repository.cancelRequests();
    for (final viewer in _viewers.toList()) {
      await _viewerLinks[viewer]?.close();
      await viewer.close();
    }
    _viewers.clear();
    _viewerLinks.clear();
    _visibleViewers.clear();
    await super.close();
  }
}
