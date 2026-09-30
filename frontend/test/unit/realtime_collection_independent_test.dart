import 'dart:async';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

class _Collection extends FakeDocumentRepository {
  int creations = 0, searches = 0;
  Completer<DocumentPage>? pending;
  Completer<DocumentSearchPage>? pendingSearch;
  final requests = <({String criteria, String? cursor})>[];
  @override
  Future<Document> create(DocumentDraft draft) {
    creations++;
    return super.create(draft);
  }

  @override
  Future<DocumentPage> list({
    int limit = 12,
    int offset = 0,
    String? cursor,
    Future<void>? cancel,
  }) {
    if (pending case final gate?) {
      pending = null;
      offsets.add(offset);
      return gate.future;
    }
    return super.list(
      limit: limit,
      offset: offset,
      cursor: cursor,
      cancel: cancel,
    );
  }

  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async {
    searches++;
    requests.add((criteria: criteria.identity, cursor: cursor));
    if (pendingSearch case final gate?) {
      pendingSearch = null;
      return gate.future;
    }
    return DocumentSearchPage(
      items: [
        DocumentSearchResult(
          id: cursor ?? 'first',
          title: 'Result',
          kind: 'document',
          tags: [],
          createdAt: DateTime.utc(2026),
          snippet: 'Text',
        ),
      ],
      total: 3,
      nextCursor: cursor == null
          ? 'second'
          : cursor == 'second'
          ? 'third'
          : null,
    );
  }
}

Future<void> _until(bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed > const Duration(seconds: 3)) {
      fail('Collection refresh did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test('realtime hint during mutation refresh retains feedback until reconciliation', () async {
    final document = Document(
      id: 'first',
      title: 'Before edit',
      description: '',
      createdAt: DateTime.utc(2026),
    );
    final repository = _Collection()..records = [document];
    final cubit = DocumentsCubit(
      repository,
      capabilities: allDocumentCapabilities,
    );
    addTearDown(cubit.close);
    cubit.setActive(true);
    await cubit.applySearch(DocumentSearchCriteria(query: 'invoice'));
    await cubit.nextSearchPage();
    final viewer = cubit.openDocument(document.id);
    await viewer.load();
    final pending = repository.pendingSearch = Completer<DocumentSearchPage>();
    viewer.editMetadata();
    viewer.setMetadataDraft(
      DocumentProperties.fromDocument(
        Document(
          id: document.id,
          title: 'After edit',
          description: '',
          createdAt: document.createdAt,
        ),
      ),
    );
    expect(await viewer.saveMetadata(), isTrue);
    expect(cubit.isLoading, isTrue);
    cubit.invalidate();
    pending.complete(DocumentSearchPage(items: const [], total: 0));
    await _until(() => !cubit.isLoading);
    expect(cubit.state.upToDate, isFalse);
    expect(cubit.state.confirmedMutation, isTrue);
    expect(cubit.state.notice, isNull);
    await cubit.closeDocument(viewer);
    await _until(() => cubit.state.upToDate && !cubit.isLoading);
    expect(cubit.state.confirmedMutation, isFalse);
    expect(cubit.state.notice, 'Results updated.');
    expect(cubit.state.ordinal, 1);
    expect(cubit.state.searchRequest!.history, isEmpty);
    expect(repository.records.single.title, 'After edit');
  });

  test(
    'queued automatic search refresh preserves viewer mutation feedback',
    () async {
      final document = Document(
        id: 'first',
        title: 'Before edit',
        description: '',
        createdAt: DateTime.utc(2026),
      );
      final repository = _Collection()..records = [document];
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      final criteria = DocumentSearchCriteria(
        query: 'invoice',
        tags: ['paid'],
        sort: DocumentSort.oldest,
      );
      await cubit.applySearch(criteria);
      final viewer = cubit.openDocument(document.id);
      await viewer.load();
      viewer.editMetadata();
      viewer.setMetadataDraft(
        DocumentProperties.fromDocument(
          Document(
            id: document.id,
            title: 'After edit',
            description: '',
            createdAt: document.createdAt,
          ),
        ),
      );
      expect(await viewer.saveMetadata(), isTrue);
      await _until(
        () => cubit.state.notice == 'Results updated.' && !cubit.isLoading,
      );
      final before = cubit.state, calls = repository.searches;
      final automaticStates = <DocumentsState>[];
      final subscription = cubit.stream.listen(automaticStates.add);
      addTearDown(subscription.cancel);
      cubit.invalidate();
      await cubit.closeDocument(viewer);
      await _until(() => repository.searches > calls && !cubit.isLoading);
      expect(cubit.state.notice, 'Results updated.');
      expect(automaticStates.where((state) => state.isLoading), isNotEmpty);
      expect(
        automaticStates.every((state) => state.notice == 'Results updated.'),
        isTrue,
      );
      expect(cubit.state.criteria!.identity, criteria.identity);
      expect(cubit.state.searchRequest!.cursor, before.searchRequest!.cursor);
      expect(cubit.state.searchRequest!.ordinal, before.searchRequest!.ordinal);
      expect(cubit.state.searchRequest!.history, before.searchRequest!.history);
      expect(cubit.state.scrollEpoch, before.scrollEpoch);
      await cubit.load();
      expect(cubit.state.notice, isNull);
    },
  );

  for (final searching in [false, true]) {
    test(
      'automatic ${searching ? 'search' : 'collection'} read cannot silently reconcile an uncertain create',
      () async {
        final repository = _Collection();
        final cubit = DocumentsCubit(
          repository,
          capabilities: allDocumentCapabilities,
        );
        addTearDown(cubit.close);
        if (searching) {
          await cubit.applySearch(DocumentSearchCriteria(query: 'invoice'));
        } else {
          await cubit.load();
        }
        repository.failure = const DocumentFailure(
          DocumentFailureKind.unavailable,
        );
        expect(await cubit.create(DocumentDraft(title: 'Uncertain')), isFalse);
        expect(repository.creations, 1);
        repository.failure = null;
        final before = searching
            ? repository.searches
            : repository.offsets.length;
        cubit.setActive(true);
        cubit.invalidate();
        await _until(
          () =>
              (searching ? repository.searches : repository.offsets.length) >
                  before &&
              !cubit.isLoading,
        );
        expect(
          await cubit.create(DocumentDraft(title: 'Repeated intent')),
          isFalse,
        );
        expect(repository.creations, 1);
        expect(cubit.saveError, contains('earlier save may have completed'));
      },
    );
  }

  test(
    'in-flight automatic list cannot remove a subsequently created row',
    () async {
      final repository = _Collection();
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      await cubit.load();
      final old = repository.pending = Completer<DocumentPage>();
      final refresh = cubit.load(automatic: true);
      expect(
        await cubit.create(DocumentDraft(title: 'Confirmed new row')),
        isTrue,
      );
      old.complete(DocumentPage(items: [], total: 0));
      await refresh;
      expect(cubit.documents.single.title, 'Confirmed new row');
      expect(cubit.total, 1);
    },
  );

  test(
    'invalidation keeps applied criteria, cursor history and scroll position',
    () async {
      final repository = _Collection();
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      final criteria = DocumentSearchCriteria(
        query: 'invoice',
        tags: ['paid'],
        sender: 'sender@example.test',
        sort: DocumentSort.oldest,
      );
      await cubit.applySearch(criteria);
      await cubit.nextSearchPage();
      final before = cubit.state, calls = repository.searches;
      cubit.setActive(true);
      cubit.invalidate();
      await _until(() => repository.searches > calls && !cubit.isLoading);
      expect(repository.requests.last, (
        criteria: criteria.identity,
        cursor: 'second',
      ));
      expect(cubit.state.searchRequest!.ordinal, 2);
      expect(cubit.state.searchRequest!.history.single.cursor, isNull);
      expect(cubit.state.scrollEpoch, before.scrollEpoch);
      expect(cubit.state.criteria!.identity, criteria.identity);
    },
  );
}
