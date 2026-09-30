import 'dart:async';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/domain/document/models/document_vocabulary.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_document_vocabulary_repository.dart';

DocumentSearchPage _result(String title, {int total = 17}) =>
    DocumentSearchPage(
      items: [
        DocumentSearchResult(
          id: title,
          title: title,
          kind: 'document',
          tags: [],
          createdAt: DateTime.utc(2026),
          snippet: '',
        ),
      ],
      total: total,
      nextCursor: 'next',
    );

final class _IntentCall {
  _IntentCall(this.criteria);
  final DocumentSearchCriteria criteria;
  final response = Completer<DocumentSearchPage>();
  bool cancelled = false;
}

final class _IntentRepository extends FakeDocumentRepository {
  final calls = <_IntentCall>[];
  bool pending = false;
  int writes = 0;
  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) {
    final call = _IntentCall(criteria);
    calls.add(call);
    cancel?.then((_) => call.cancelled = true);
    if (!pending) call.response.complete(_result(criteria.query));
    return call.response.future;
  }

  @override
  Future<Document> create(DocumentDraft draft) {
    writes++;
    return super.create(draft);
  }
}

void main() {
  late _IntentRepository repository;
  late DocumentsCubit cubit;
  setUp(() {
    repository = _IntentRepository();
    cubit = DocumentsCubit(repository, capabilities: allDocumentCapabilities);
  });
  tearDown(() => cubit.close());

  testWidgets('type change uses pending text and fences old results', (
    tester,
  ) async {
    await cubit.applySearch(DocumentSearchCriteria(query: 'committed'));
    repository.pending = true;
    final previous = cubit.setKinds([DocumentKind.email]);
    cubit.editTerm('latest', composing: false);
    final current = cubit.setKinds([
      DocumentKind.document,
      DocumentKind.letter,
    ]);
    await tester.pump();
    expect(repository.calls[1].cancelled, isTrue);
    expect(repository.calls.last.criteria.query, 'latest');
    expect(repository.calls.last.criteria.kinds, [
      DocumentKind.document,
      DocumentKind.letter,
    ]);
    repository.calls.last.response.complete(_result('new types', total: 2));
    await current;
    repository.calls[1].response.complete(_result('old emails', total: 99));
    await previous;
    await tester.pump(const Duration(milliseconds: 301));
    expect(repository.calls, hasLength(3));
    expect(cubit.state.results.single.title, 'new types');
    expect(cubit.state.total, 2);
    expect(cubit.state.criteria!.kinds, [
      DocumentKind.document,
      DocumentKind.letter,
    ]);
  });

  testWidgets(
    'A completes after typing B but before debounce: committed snapshot stays coherent',
    (tester) async {
      await cubit.applySearch(DocumentSearchCriteria(query: 'committed'));
      repository.pending = true;
      final a = cubit.applySearch(DocumentSearchCriteria(query: 'A'));
      cubit.editTerm('B', composing: false);
      await tester.pump();
      expect(repository.calls[1].cancelled, isTrue);
      repository.calls[1].response.complete(_result('stale A', total: 99));
      await a;
      expect(cubit.state.criteria!.query, 'committed');
      expect(cubit.state.results.single.title, 'committed');
      expect(cubit.state.total, 17);
      expect(cubit.state.desiredCriteria.query, 'B');
      expect(cubit.state.canPaginate, isFalse);
      await tester.pump(const Duration(milliseconds: 299));
      expect(repository.calls, hasLength(2));
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.calls.last.criteria.query, 'B');
      final immediate = cubit.submitSearch();
      final refresh = cubit.load();
      expect(repository.calls, hasLength(3));
      repository.calls.last.response.complete(_result('B', total: 4));
      await Future.wait([immediate, refresh]);
      expect(cubit.state.criteria!.query, 'B');
      expect(cubit.state.results.single.title, 'B');
      expect(cubit.state.total, 4);
      expect(cubit.state.upToDate, isTrue);
    },
  );

  for (final composing in [false, true]) {
    testWidgets(
      'a ${composing ? 'composing' : 'invalid'} edit destroys the exact failed retry target',
      (tester) async {
        repository.pending = true;
        final failed = cubit.applySearch(
          DocumentSearchCriteria(query: 'failed'),
        );
        repository.calls.single.response.completeError(
          const DocumentFailure(DocumentFailureKind.unavailable),
        );
        await failed;
        expect(cubit.state.failedRequest, isNotNull);
        cubit.editTerm(composing ? '日本' : '\ud800', composing: composing);
        await cubit.retryCollection();
        await cubit.load();
        await cubit.submitSearch();
        await tester.pump(const Duration(seconds: 30));
        expect(repository.calls, hasLength(1));
        expect(cubit.state.failedRequest, isNull);
        expect(cubit.state.intentBlocked, isTrue);
        expect(cubit.state.hasSnapshot, isFalse);
      },
    );
  }

  testWidgets(
    'composition plus sort, tag and realtime converge on unchanged-character commit',
    (tester) async {
      await cubit.applySearch(DocumentSearchCriteria(query: 'old'));
      cubit.setActive(true);
      cubit.editTerm('日本', composing: true);
      await cubit.setSort(DocumentSort.title);
      await cubit.selectOption(
        DocumentVocabularyField.tag,
        vocabularyOption(1, value: '\ufefftag'),
      );
      for (var index = 0; index < 10; index++) {
        cubit.invalidate();
      }
      await tester.pump(const Duration(seconds: 20));
      expect(repository.calls, hasLength(1));
      expect(tester.binding.transientCallbackCount, 0);
      cubit.editTerm('日本', composing: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.calls, hasLength(2));
      final criteria = repository.calls.last.criteria;
      expect(criteria.query, '日本');
      expect(criteria.sort, DocumentSort.title);
      expect(criteria.tags, ['\ufefftag']);
      await tester.pump(const Duration(seconds: 3));
      expect(repository.calls, hasLength(2));
    },
  );

  testWidgets(
    'invalidation arriving during a read gets one subsequent refresh',
    (tester) async {
      await cubit.applySearch(DocumentSearchCriteria(query: 'current'));
      cubit.setActive(true);
      repository.pending = true;
      final read = cubit.load();
      cubit.invalidate();
      repository.calls.last.response.complete(_result('older'));
      await read;
      expect(cubit.state.upToDate, isFalse);
      await tester.pump(const Duration(milliseconds: 350));
      expect(repository.calls, hasLength(3));
      expect(repository.calls.last.criteria.query, 'current');
      repository.calls.last.response.complete(_result('fresh'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(cubit.state.results.single.title, 'fresh');
      expect(cubit.state.upToDate, isTrue);
      expect(repository.calls, hasLength(3));
    },
  );

  testWidgets(
    'confirmed create uses pending desired term and failed read retains honest saved status',
    (tester) async {
      await cubit.applySearch(DocumentSearchCriteria(query: 'old'));
      cubit.editTerm('new', composing: false);
      repository.pending = true;
      final creation = cubit.create(DocumentDraft(title: 'Saved'));
      await tester.pump();
      expect(repository.calls.last.criteria.query, 'new');
      repository.calls.last.response.completeError(
        const DocumentFailure(DocumentFailureKind.unavailable),
      );
      expect(await creation, isTrue);
      expect(cubit.state.status, 'Change saved. Could not update documents');
      expect(cubit.state.results.single.title, 'old');
      expect(cubit.state.criteria!.query, 'old');
      final retry = cubit.retryCollection();
      repository.calls.last.response.complete(_result('new'));
      await retry;
      expect(repository.writes, 1);
      expect(cubit.state.confirmedMutation, isFalse);
    },
  );

  testWidgets(
    'clearing only the term preserves exact filters and sort; clear all ignores stale page',
    (tester) async {
      await cubit.applySearch(
        DocumentSearchCriteria(query: 'term', sort: DocumentSort.title),
      );
      await cubit.selectOption(
        DocumentVocabularyField.sender,
        vocabularyOption(7, value: '\ufeffSender\ufeff'),
      );
      cubit.editTerm('', composing: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.calls.last.criteria.query, '');
      expect(repository.calls.last.criteria.sender, '\ufeffSender\ufeff');
      expect(
        repository.calls.last.criteria.senderMatch,
        DocumentAddressMatch.exact,
      );
      expect(repository.calls.last.criteria.sort, DocumentSort.title);
      repository.pending = true;
      final next = cubit.nextSearchPage();
      final stale = repository.calls.last;
      await cubit.clearSearch();
      stale.response.complete(_result('stale'));
      await next;
      expect(cubit.state.searching, isFalse);
      expect(cubit.state.hasSnapshot, isTrue);
      expect(cubit.state.results, isEmpty);
      expect(cubit.state.desiredCriteria.filterCount, 0);
    },
  );
}
