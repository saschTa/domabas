import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

DocumentSearchPage page(String id, {String? next, int? total = 100}) =>
    DocumentSearchPage(
      items: [
        DocumentSearchResult(
          id: id,
          title: id,
          kind: 'document',
          tags: [],
          createdAt: DateTime.utc(2026),
          snippet: 'needle',
        ),
      ],
      total: total,
      nextCursor: next,
    );
Document record() => Document(
  id: 'file',
  title: 'Original',
  description: '',
  createdAt: DateTime.utc(2026),
  file: DocumentFile(
    originalFilename: 'scan.png',
    mediaType: 'image/png',
    size: 3,
    sha256: 'hash',
    ingestedAt: DateTime.utc(2026),
    uploaderId: 'user',
  ),
);
DocumentProperties changed(Document document) =>
    DocumentProperties.fromDocument(
      Document(
        id: document.id,
        title: 'Changed',
        description: document.description,
        createdAt: document.createdAt,
      ),
    );

void main() {
  late SearchRepository repository;
  late DocumentsCubit cubit;
  setUp(() {
    repository = SearchRepository()
      ..records = [record()]
      ..originals['file'] = Uint8List.fromList([1, 2, 3])
      ..ocr['file'] = const DocumentOcr(
        status: 'available',
        revision: 1,
        text: 'needle',
        origin: 'machine',
        reason: null,
        semanticIndexing: 'ready',
      );
    cubit = DocumentsCubit(repository, capabilities: allDocumentCapabilities);
  });
  tearDown(() => cubit.close());

  test(
    'type selections are canonical, immutable and part of search identity',
    () {
      final criteria = DocumentSearchCriteria(
        kinds: [
          DocumentKind.letter,
          DocumentKind.document,
          DocumentKind.letter,
        ],
      );
      expect(criteria.kinds, [DocumentKind.document, DocumentKind.letter]);
      expect(criteria.filterCount, 1);
      expect(() => criteria.kinds.clear(), throwsUnsupportedError);
      expect(criteria.copyWith(query: 'invoice').kinds, criteria.kinds);
      expect(criteria.identity, isNot(DocumentSearchCriteria().identity));
      expect(
        DocumentSearchCriteria(kinds: DocumentKind.values).identity,
        DocumentSearchCriteria().identity,
      );
    },
  );

  test(
    'unknown totals preserve next, previous, first and refresh cursors',
    () async {
      repository.omitTotal = true;
      await cubit.applySearch(DocumentSearchCriteria(query: 'invoice'));
      expect(cubit.state.totalKnown, isFalse);
      await cubit.nextSearchPage();
      expect(cubit.state.ordinal, 2);
      await cubit.load(automatic: true);
      expect(repository.calls.last.cursor, 'page-2');
      expect(cubit.state.totalKnown, isFalse);
      await cubit.previousSearchPage();
      expect(repository.calls.last.cursor, isNull);
      await cubit.nextSearchPage();
      await cubit.firstSearchPage();
      expect(cubit.state.ordinal, 1);
      expect(cubit.state.totalKnown, isFalse);
    await cubit.clearSearch();
      expect(cubit.state.totalKnown, isTrue);
    },
  );

  test('type changes restart pages and survive refresh until reset', () async {
    await cubit.applySearch(
      DocumentSearchCriteria(query: 'invoice', tags: ['work']),
    );
    await cubit.nextSearchPage();
    await cubit.setKinds([DocumentKind.document, DocumentKind.letter]);
    expect(repository.calls.last.cursor, isNull);
    expect(cubit.state.ordinal, 1);
    expect(cubit.state.desiredCriteria.query, 'invoice');
    expect(cubit.state.desiredCriteria.tags, ['work']);
    await cubit.nextSearchPage();
    await cubit.load(automatic: true);
    expect(repository.calls.last.cursor, 'page-2');
    expect(cubit.state.criteria!.kinds, [
      DocumentKind.document,
      DocumentKind.letter,
    ]);
    await cubit.clearKinds();
    expect(cubit.state.criteria!.kinds, isEmpty);
    expect(cubit.state.criteria!.tags, ['work']);
    await cubit.setKinds([DocumentKind.email]);
    await cubit.resetFilters();
    expect(cubit.state.desiredCriteria.filterCount, 0);
    expect(cubit.state.desiredCriteria.query, 'invoice');
    await cubit.clearSearch();
    await cubit.setKinds([DocumentKind.email]);
    expect(cubit.state.searching, isTrue);
    expect(cubit.state.criteria!.query, isEmpty);
    await cubit.clearKinds();
    expect(cubit.state.searching, isFalse);
  });

  test(
    'criteria preserve Unicode tags while normalizing ASCII and resolving sort',
    () {
      final criteria = DocumentSearchCriteria(
        query: ' invoice ',
        tags: [' WORK ', 'work', 'İ', 'ΟΣ'],
      );
      expect(criteria.tags, ['work', 'İ', 'ΟΣ']);
      expect(criteria.sort, DocumentSort.relevance);
      expect(
        DocumentSearchCriteria().copyWith(query: 'invoice').sort,
        DocumentSort.relevance,
      );
      expect(criteria.copyWith(query: '').sort, DocumentSort.newest);
      expect(
        criteria.copyWith(sort: DocumentSort.title).copyWith(query: '').sort,
        DocumentSort.title,
      );
      expect(DocumentSearchCriteria.validateTerm('😀' * 1000), isNull);
      expect(DocumentSearchCriteria.validateTerm('😀' * 1001), isNotNull);
      expect(DocumentSearchCriteria.validateAddress('a\u0085b'), isNotNull);
      expect(() => criteria.tags.clear(), throwsUnsupportedError);
    },
  );

  test(
    'failed Next preserves committed history and retries the failed target',
    () async {
      await cubit.applySearch(DocumentSearchCriteria(query: 'needle'));
      repository.error = const DocumentFailure(DocumentFailureKind.unavailable);
      await cubit.nextSearchPage();
      expect(cubit.state.ordinal, 1);
      expect(cubit.state.results.single.id, 'first');
      expect(cubit.state.searchRequest!.history, isEmpty);
      expect(cubit.state.failedRequest!.cursor, 'page-2');
      repository.error = null;
      await cubit.retryCollection();
      expect(repository.calls.map((call) => call.cursor), [
        null,
        'page-2',
        'page-2',
      ]);
      expect(cubit.state.ordinal, 2);
      expect(cubit.state.searchRequest!.history.single.ordinal, 1);
      expect(cubit.state.failedRequest, isNull);
    },
  );

  test(
    'history retains 50 absolute positions and first page resets it',
    () async {
      await cubit.applySearch(DocumentSearchCriteria(query: 'needle'));
      for (var i = 0; i < 55; i++) {
        await cubit.nextSearchPage();
      }
      expect(cubit.state.ordinal, 56);
      expect(cubit.state.searchRequest!.history, hasLength(50));
      expect(cubit.state.searchRequest!.history.first.ordinal, 6);
      await cubit.previousSearchPage();
      expect(cubit.state.ordinal, 55);
      expect(repository.calls.last.cursor, 'page-55');
      await cubit.firstSearchPage();
      expect(cubit.state.ordinal, 1);
      expect(cubit.state.searchRequest!.history, isEmpty);
      expect(repository.calls.last.cursor, isNull);
    },
  );

  test(
    'empty later page recovers once and stale fallback cannot overwrite Clear',
    () async {
      await cubit.applySearch(DocumentSearchCriteria(query: 'needle'));
      repository.pending = [];
      final next = cubit.nextSearchPage();
      repository.pending![0].complete(DocumentSearchPage(items: [], total: 1));
      await Future<void>.delayed(Duration.zero);
      expect(repository.pending, hasLength(2));
      expect(repository.calls.last.cursor, isNull);
      await cubit.clearSearch();
      repository.pending![1].complete(page('stale fallback'));
      await next;
      expect(cubit.state.searching, isFalse);
      expect(cubit.documents.single.id, 'file');
      expect(cubit.state.results, isEmpty);
    },
  );

  test(
    'empty later page recovery commits page one with notice and no history',
    () async {
      await cubit.applySearch(DocumentSearchCriteria(query: 'needle'));
      repository.pending = [];
      final next = cubit.nextSearchPage();
      repository.pending![0].complete(DocumentSearchPage(items: [], total: 1));
      await Future<void>.delayed(Duration.zero);
      repository.pending![1].complete(page('fresh', total: 1));
      await next;
      expect(cubit.state.ordinal, 1);
      expect(cubit.state.notice, contains('Results changed'));
      expect(cubit.state.searchRequest!.history, isEmpty);
      expect(cubit.state.nextCursor, isNull);
    },
  );

  test(
    'rapid Search Sort Clear ignores superseded success and error',
    () async {
      repository.pending = [];
      final first = cubit.applySearch(DocumentSearchCriteria(query: 'first'));
      final second = cubit.applySearch(
        DocumentSearchCriteria(query: 'second', sort: DocumentSort.title),
      );
      await cubit.clearSearch();
      repository.pending![1].completeError(
        const DocumentFailure(DocumentFailureKind.unavailable),
      );
      repository.pending![0].complete(page('stale'));
      await Future.wait([first, second]);
      expect(repository.searchCancelled.take(2), [true, true]);
      expect(cubit.state.searching, isFalse);
      expect(cubit.state.error, isNull);
      expect(cubit.documents.single.id, 'file');
    },
  );

  test('collection cancellation leaves viewer download alive; scope close cancels both', () async {
    repository.downloadPending = Completer<Uint8List>();
    final viewer = cubit.openDocument('file');
    final loading = viewer.load();
    await Future<void>.delayed(Duration.zero);
    repository.pending = [];
    final first = cubit.applySearch(DocumentSearchCriteria(query: 'first'));
    final second = cubit.applySearch(DocumentSearchCriteria(query: 'second'));
    await Future<void>.delayed(Duration.zero);
    expect(repository.searchCancelled, [true, false]);
    expect(repository.downloadCancelled, isFalse);
    await cubit.close();
    await Future<void>.delayed(Duration.zero);
    expect(repository.searchCancelled, [true, true]);
    expect(repository.downloadCancelled, isTrue);
    expect(repository.cancelled, isTrue);
    repository.downloadPending!.complete(Uint8List.fromList([4]));
    for (final pending in repository.pending!) {
      pending.complete(page('late'));
    }
    await Future.wait([first, second, loading]);
    expect(cubit.state.results, isEmpty);
  });

  test(
    'hydration and no-edit viewer return preserve later search page and scroll',
    () async {
      await cubit.applySearch(
        DocumentSearchCriteria(query: 'needle', tags: ['work']),
      );
      await cubit.nextSearchPage();
      final before = cubit.state;
      final viewer = cubit.openDocument('file');
      await viewer.load();
      await viewer.load();
      await cubit.closeDocument(viewer);
      expect(repository.calls, hasLength(2));
      expect(cubit.state.searchRequest, same(before.searchRequest));
      expect(cubit.state.scrollEpoch, before.scrollEpoch);
      expect(cubit.state.results, before.results);
    },
  );

  test('completed mutation notice survives viewer return until an explicit refresh', () async {
    await cubit.applySearch(
      DocumentSearchCriteria(query: 'needle', tags: ['work']),
    );
    await cubit.nextSearchPage();
    final viewer = cubit.openDocument('file');
    await viewer.load();
    repository.pending = [];
    viewer.editMetadata();
    viewer.setMetadataDraft(changed(record()));
    expect(await viewer.saveMetadata(), isTrue);
    expect(repository.pending, hasLength(1));
    final refreshed = cubit.stream.firstWhere((state) => !state.isLoading);
    repository.pending!.single.complete(page('remaining', total: 1));
    await refreshed;
    expect(cubit.state.notice, 'Results updated.');
    expect(cubit.state.total, 1);
    expect(cubit.state.ordinal, 1);
    expect(cubit.state.searchRequest!.history, isEmpty);
    final committed = cubit.state.searchRequest;
    await cubit.closeDocument(viewer);
    cubit.setLayout(DocumentLayout.list);
    expect(cubit.state.notice, 'Results updated.');
    expect(cubit.state.total, 1);
    expect(cubit.state.searchRequest, same(committed));
    final refresh = cubit.load();
    expect(cubit.state.notice, isNull);
    repository.pending!.last.complete(page('remaining', total: 1));
    await refresh;
    expect(cubit.state.notice, isNull);
    expect(cubit.state.criteria!.query, 'needle');
    expect(cubit.state.criteria!.tags, ['work']);
    expect(repository.writes, 1);
  });

  for (final operation in ['metadata', 'ocr', 'create']) {
    test(
      '$operation mutation refreshes first search page and never repeats confirmed writes on refresh failure',
      () async {
        await cubit.applySearch(
          DocumentSearchCriteria(query: 'needle', tags: ['work']),
        );
        await cubit.nextSearchPage();
        final viewer = cubit.openDocument('file');
        await viewer.load();
        repository.error = const DocumentFailure(
          DocumentFailureKind.unavailable,
        );
        if (operation == 'metadata') {
          viewer.editMetadata();
          viewer.setMetadataDraft(changed(record()));
          expect(await viewer.saveMetadata(), isTrue);
        } else if (operation == 'ocr') {
          viewer.editOcr();
          viewer.setOcrDraft('no longer matches');
          expect(await viewer.saveOcr(), isTrue);
        } else {
          expect(await cubit.create(DocumentDraft(title: 'Unrelated')), isTrue);
        }
        await Future<void>.delayed(Duration.zero);
        expect(repository.calls, hasLength(3));
        expect(repository.calls.last.cursor, isNull);
        expect(cubit.state.failedRequest!.ordinal, 1);
        expect(cubit.state.results.single.id, 'page-2');
        repository.error = null;
        await cubit.retryCollection();
        expect(cubit.state.ordinal, 1);
        expect(repository.writes, 1);
        await cubit.closeDocument(viewer);
      },
    );
  }

  for (final operation in ['metadata', 'ocr', 'delete']) {
    for (final delayed in [false, true]) {
      test(
        '$operation uncertain mutation reconciles ${delayed ? 'later' : 'automatically'} exactly once',
        () async {
          await cubit.applySearch(DocumentSearchCriteria(query: 'needle'));
          await cubit.nextSearchPage();
          final viewer = cubit.openDocument('file');
          await viewer.load();
          repository.uncertain = operation;
          repository.failReconciliation = delayed;
          if (operation == 'metadata') {
            viewer.editMetadata();
            viewer.setMetadataDraft(changed(record()));
            await viewer.saveMetadata();
          }
          if (operation == 'ocr') {
            viewer.editOcr();
            viewer.setOcrDraft('changed OCR');
            await viewer.saveOcr();
          }
          if (operation == 'delete') {
            await viewer.delete();
          }
          if (delayed) {
            expect(cubit.state.ordinal, 2);
            expect(repository.calls, hasLength(2));
            repository.failReconciliation = false;
            if (operation == 'ocr') {
              await viewer.loadOcr();
            } else {
              await viewer.load();
            }
          }
          await Future<void>.delayed(Duration.zero);
          expect(repository.calls, hasLength(3));
          expect(repository.calls.last.cursor, isNull);
          expect(cubit.state.ordinal, 1);
          expect(repository.writes, 1);
          if (operation != 'delete') {
            await viewer.load();
            await viewer.loadOcr();
          }
          expect(repository.calls, hasLength(3));
          await cubit.closeDocument(viewer);
        },
      );
    }
  }

  test(
    'delete starts refresh before immediate deleted-state route disposal',
    () async {
      await cubit.applySearch(DocumentSearchCriteria(query: 'needle'));
      await cubit.nextSearchPage();
      final viewer = cubit.openDocument('file');
      await viewer.load();
      repository.pending = [];
      final disposed = Completer<void>();
      final subscription = viewer.stream.listen((state) async {
        if (state.deleted) {
          await cubit.closeDocument(viewer);
          disposed.complete();
        }
      });
      final deleting = viewer.delete();
      await disposed.future;
      expect(repository.pending, hasLength(1));
      repository.pending!.single.complete(
        DocumentSearchPage(items: [], total: 0),
      );
      await deleting;
      expect(cubit.state.ordinal, 1);
      expect(cubit.state.results, isEmpty);
      expect(repository.writes, 1);
      await subscription.cancel();
    },
  );
}

final class SearchCall {
  SearchCall(this.criteria, this.cursor);
  final DocumentSearchCriteria criteria;
  final String? cursor;
}

class SearchRepository extends FakeDocumentRepository {
  bool omitTotal = false;
  final calls = <SearchCall>[];
  final searchCancelled = <bool>[];
  List<Completer<DocumentSearchPage>>? pending;
  Completer<Uint8List>? downloadPending;
  bool downloadCancelled = false;
  DocumentFailure? error;
  String? uncertain;
  bool failReconciliation = false;
  int writes = 0;
  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async {
    calls.add(SearchCall(criteria, cursor));
    final index = searchCancelled.length;
    searchCancelled.add(false);
    unawaited(
      cancel?.then((_) {
        searchCancelled[index] = true;
      }),
    );
    if (pending case final requests?) {
      final completer = Completer<DocumentSearchPage>();
      requests.add(completer);
      return completer.future;
    }
    if (error case final failure?) {
      throw failure;
    }
    final ordinal = cursor == null ? 1 : int.parse(cursor.substring(5));
    return page(
      cursor ?? 'first',
      next: 'page-${ordinal + 1}',
      total: omitTotal ? null : 100,
    );
  }

  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) {
    cancel?.then((_) => downloadCancelled = true);
    return downloadPending?.future ?? super.download(document, cancel: cancel);
  }

  @override
  Future<Document> getById(String id, {Future<void>? cancel}) {
    if (failReconciliation) {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    }
    return super.getById(id, cancel: cancel);
  }

  @override
  Future<DocumentOcr> getOcr(String id, {Future<void>? cancel}) {
    if (failReconciliation) {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    }
    return super.getOcr(id, cancel: cancel);
  }

  @override
  Future<Document> update(
    Document original,
    DocumentProperties properties, {
    Future<void>? cancel,
  }) async {
    writes++;
    final value = await super.update(original, properties, cancel: cancel);
    if (uncertain == 'metadata') {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    }
    return value;
  }

  @override
  Future<DocumentOcr> updateOcr(
    String id,
    int revision,
    String text, {
    Future<void>? cancel,
  }) async {
    writes++;
    final value = await super.updateOcr(id, revision, text, cancel: cancel);
    if (uncertain == 'ocr') {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    }
    return value;
  }

  @override
  Future<void> delete(String id, {Future<void>? cancel}) async {
    writes++;
    await super.delete(id, cancel: cancel);
    if (uncertain == 'delete') {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    }
  }

  @override
  Future<Document> create(DocumentDraft draft) async {
    writes++;
    return super.create(draft);
  }
}
