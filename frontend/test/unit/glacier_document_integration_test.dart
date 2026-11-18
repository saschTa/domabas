import 'dart:async';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/domain/document/models/document_vocabulary.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/models/document_search_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

Document record({String state = 'failed', String? failure}) => Document(
  id: 'document',
  title: 'Household insurance',
  description: '',
  createdAt: DateTime.utc(2026),
  processing: DocumentProcessing(
    state: state,
    stage: 'ocr',
    generation: 2,
    configurationRevision: 1,
    updatedAt: DateTime.utc(2026),
    failureCode: failure,
    ocrEngine: '',
    ocrVersion: '',
    ocrModel: '',
    ocrLanguage: '',
    ocrSegmentation: '',
    embeddingModel: '',
    embeddingDigest: '',
    embeddingDimensions: 0,
  ),
);

final class Repository extends FakeDocumentRepository {
  final searches = <DocumentSearchCriteria>[];
  int retries = 0;
  Completer<Document>? currentRead;
  bool readCancelled = false;
  DocumentFailure? retryFailure;
  @override
  Future<Document> getById(String id, {Future<void>? cancel}) async {
    if (cancel != null) {
      unawaited(
        cancel.then((_) {
          readCancelled = true;
        }),
      );
    }
    if (currentRead case final pending?) {
      reads++;
      return pending.future;
    }
    return super.getById(id, cancel: cancel);
  }

  @override
  Future<void> retry(String id, {Future<void>? cancel}) async {
    retries++;
    if (retryFailure case final failure?) throw failure;
  }

  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async {
    searches.add(criteria);
    return DocumentSearchPage(
      items: [
        DocumentSearchResult(
          id: 'document',
          title: 'Household insurance',
          kind: 'document',
          tags: [],
          createdAt: DateTime.utc(2026),
          snippet: 'Relevant original text',
          processingState: 'failed',
        ),
      ],
      total: null,
    );
  }
}

void main() {
  test('draft edits issue no request; apply commits query and opaque selections once', () async {
    final repository = Repository()..records = [record()];
    final cubit = DocumentsCubit(
      repository,
      capabilities: allDocumentCapabilities,
    );
    await cubit.load();
    var draft = DocumentSearchDraft.fromState(cubit.state);
    const tag = DocumentVocabularyOption(key: 'opaque-tag', value: 'Haushalt');
    const sender = DocumentVocabularyOption(
      key: 'opaque-sender',
      value: 'Name <Mail@Example.test>',
    );
    draft = draft
        .select(DocumentVocabularyField.tag, tag)
        .select(DocumentVocabularyField.sender, sender);
    draft = draft.withCriteria(
      draft.desiredCriteria.copyWith(
        query: 'insurance',
        kinds: [DocumentKind.letter],
      ),
    );
    expect(repository.searches, isEmpty);
    expect(cubit.state.desiredCriteria.query, isEmpty);
    await cubit.applySearch(
      draft.desiredCriteria,
      selectedTags: draft.selectedTags,
      selectedSender: draft.selectedSender,
      replaceSelections: true,
    );
    expect(repository.searches, hasLength(1));
    expect(repository.searches.single.sender, sender.value);
    expect(repository.searches.single.senderMatch, DocumentAddressMatch.exact);
    expect(repository.searches.single.tags, [tag.value]);
    expect(cubit.state.selectedTags.single.key, tag.key);
    expect(cubit.state.selectedSender?.key, sender.key);
    expect(cubit.state.totalKnown, isFalse);
    await cubit.close();
  });

  test('inline retry requires both read and retry capabilities', () async {
    for (final capabilities in [
      const DocumentCapabilities(read: true),
      const DocumentCapabilities(retry: true),
    ]) {
      final repository = Repository()..records = [record()];
      final cubit = DocumentsCubit(repository, capabilities: capabilities);
      await cubit.load();
      await cubit.retryDocument('document');
      expect(repository.retries, 0);
      expect(repository.reads, 0);
      await cubit.close();
    }
  });

  test(
    'inline retry rechecks encrypted and already completed records',
    () async {
      for (final current in [
        record(failure: 'encrypted_pdf'),
        record(state: 'ready'),
      ]) {
        final repository = Repository()..records = [record()];
        final cubit = DocumentsCubit(
          repository,
          capabilities: allDocumentCapabilities,
        );
        await cubit.load();
        repository.records = [current];
        await cubit.retryDocument('document');
        expect(repository.retries, 0);
        expect(repository.reads, 1);
        expect(cubit.state.retryingIds, isEmpty);
        if (current.processing?.failureCode != null) {
          expect(cubit.state.notice, contains('password'));
        }
        await cubit.close();
      }
    },
  );

  test(
    'duplicate retry is suppressed and owner closure cancels admission',
    () async {
      final pending = Completer<Document>();
      final repository = Repository()
        ..records = [record()]
        ..currentRead = pending;
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      await cubit.load();
      final first = cubit.retryDocument('document');
      await cubit.retryDocument('document');
      expect(repository.reads, 1);
      expect(cubit.state.retryingIds, {'document'});
      await cubit.close();
      await Future<void>.delayed(Duration.zero);
      expect(repository.readCancelled, isTrue);
      pending.complete(record());
      await first;
      expect(repository.retries, 0);
      expect(repository.thumbnailReads, 0);
    },
  );

  test('successful inline retry refreshes current search without allocating reader', () async {
    final pending = Completer<Document>();
    final repository = Repository()
      ..records = [record()]
      ..currentRead = pending;
    final cubit = DocumentsCubit(
      repository,
      capabilities: allDocumentCapabilities,
    );
    await cubit.load();
    final retry = cubit.retryDocument('document');
    await cubit.applySearch(DocumentSearchCriteria(query: 'new intent'));
    pending.complete(record());
    await retry;
    expect(repository.retries, 1);
    expect(repository.searches.map((value) => value.query), [
      'new intent',
      'new intent',
    ]);
    expect(cubit.state.desiredCriteria.query, 'new intent');
    expect(repository.reads, 1);
    expect(repository.thumbnailReads, 0);
    expect(cubit.state.retryingIds, isEmpty);
    await cubit.close();
  });

  test(
    'uncertain retry failure is shown without automatic duplicate writes',
    () async {
      final repository = Repository()
        ..records = [record()]
        ..retryFailure = const DocumentFailure(DocumentFailureKind.unavailable);
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      await cubit.load();
      await cubit.retryDocument('document');
      expect(repository.retries, 1);
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.documents, hasLength(1));
      expect(cubit.state.retryingIds, isEmpty);
      await cubit.load();
      expect(repository.retries, 1);
      await cubit.close();
    },
  );
}
