import 'dart:async';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

void main() {
  testWidgets(
    'Escape clears only the modal draft then closes without applying',
    (tester) async {
      final repository = _ActionsRepository();
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      await cubit.applySearch(
        DocumentSearchCriteria(
          query: 'committed',
          kinds: [DocumentKind.letter],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: DocumentsScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('documentFilters')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('documentSearchTerm'));
      await tester.enterText(field, 'draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.byKey(const Key('documentSearchDialog')), findsOneWidget);
      expect(cubit.state.desiredCriteria.query, 'committed');
      expect(cubit.state.desiredCriteria.kinds, [DocumentKind.letter]);
      expect(repository.searches, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('documentSearchDialog')), findsNothing);
      expect(repository.searches, 1);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'inline retry at $width preserves card bounds and never opens a reader',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final repository = _ActionsRepository()..records = [_failed()];
        final cubit = DocumentsCubit(
          repository,
          capabilities: allDocumentCapabilities,
        );
        addTearDown(cubit.close);
        await cubit.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: DocumentsScreen(cubit: cubit)),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const Key('document-failed'));
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(card);
        final pending = repository.pending = Completer<Document>();
        await tester.tap(find.byTooltip('Retry processing Insurance'));
        await tester.pump();
        expect(cubit.state.retryingIds, {'failed'});
        expect(tester.getRect(card), bounds);
        expect(find.byKey(const Key('documentDetails')), findsNothing);
        expect(repository.reads, 1);
        expect(repository.thumbnailReads, 0);
        pending.complete(_failed());
        await tester.pumpAndSettle();
        expect(repository.retries, 1);
        expect(find.byKey(const Key('documentDetails')), findsNothing);
        expect(tester.getRect(card), bounds);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Document _failed() => Document(
  id: 'failed',
  title: 'Insurance',
  description: '',
  createdAt: DateTime.utc(2026),
  processing: DocumentProcessing(
    state: 'failed',
    stage: 'ocr',
    generation: 1,
    configurationRevision: 1,
    updatedAt: DateTime.utc(2026),
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

final class _ActionsRepository extends FakeDocumentRepository {
  int searches = 0, retries = 0;
  Completer<Document>? pending;
  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async {
    searches++;
    return DocumentSearchPage(items: [], total: 0);
  }

  @override
  Future<Document> getById(String id, {Future<void>? cancel}) async {
    if (pending case final value?) {
      reads++;
      return value.future;
    }
    return super.getById(id, cancel: cancel);
  }

  @override
  Future<void> retry(String id, {Future<void>? cancel}) async {
    retries++;
  }
}
