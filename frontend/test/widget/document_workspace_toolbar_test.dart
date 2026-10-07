import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/presentation/document/widgets/documents_workspace_toolbar.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_document_vocabulary_repository.dart';

void main() {
  for (final width in [390.0, 1512.0]) {
    testWidgets(
      'fixed document pane preserves search and scroll after direct preview at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 982);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final repository = _ToolbarDocumentsRepository();
        final cubit = DocumentsCubit(
          repository,
          capabilities: allDocumentCapabilities,
        );
        addTearDown(cubit.close);
        await cubit.load();
        final vocabulary = FakeDocumentVocabularyRepository();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: AppWorkspaceShell(
              groups: const [],
              selectedId: 'documents',
              onSelected: (_) {},
              libraryPicker: const Text('Personal library'),
              accountLabel: 'person@example.test',
              onLogout: () {},
              toolbarBuilder: (context, libraryPicker, workspaceActions) =>
                  DocumentsWorkspaceToolbar(
                    cubit: cubit,
                    vocabulary: vocabulary,
                    libraryPicker: libraryPicker,
                    workspaceActions: workspaceActions,
                  ),
              child: DocumentsScreen(cubit: cubit, shellToolbar: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('documentSearchTerm'));
        final collection = find.byKey(const Key('documentCollectionScroll'));
        expect(field, findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DocumentsScreen),
            matching: find.text('Documents'),
          ),
          findsNothing,
        );
        final surface = tester.getRect(find.byKey(const Key('pageSurface')));
        final first = tester.getRect(find.byType(DocumentCollectionCard).first);
        expect(first.top - surface.top, 18);
        expect(find.byKey(const Key('documentCount')), findsNothing);
        await tester.enterText(field, 'invoice');
        await tester.tap(find.byKey(const Key('applyDocumentSearch')));
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(field).controller;
        final searchPosition = tester.getRect(field);
        final scroll = tester
            .state<ScrollableState>(
              find
                  .descendant(of: collection, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        await tester.drag(collection, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(scroll.pixels, greaterThan(200));
        expect(
          find.byKey(const Key('documentCount')).hitTestable(),
          findsNothing,
        );
        expect(tester.getRect(field), searchPosition);
        expect(tester.getRect(find.byKey(const Key('pageSurface'))), surface);
        final offset = scroll.pixels;
        final card = find.byType(DocumentCollectionCard).hitTestable().first;
        final document = tester.widget<DocumentCollectionCard>(card).document;
        await tester.tap(find.byKey(Key('document-${document.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('documentWindow')), findsOneWidget);
        expect(find.byKey(const Key('documentDetails')), findsOneWidget);
        expect(
          find.byKey(const Key('documentInspectorPanel')),
          width >= 1100 ? findsOneWidget : findsNothing,
        );
        expect(repository.reads, 1);
        await tester.tap(find.byKey(const Key('closeDocument')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller, same(controller));
        expect(controller!.text, 'invoice');
        expect(scroll.pixels, closeTo(offset, .01));
        expect(cubit.state.desiredCriteria.query, 'invoice');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _ToolbarDocumentsRepository extends FakeDocumentRepository {
  _ToolbarDocumentsRepository() {
    records = List.generate(
      48,
      (index) => Document(
        id: 'document-$index',
        title: 'Invoice $index',
        description: '',
        createdAt: DateTime.utc(2026),
      ),
    );
  }

  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async => DocumentSearchPage(
    items: records
        .take(limit)
        .map(
          (document) => DocumentSearchResult(
            id: document.id,
            title: document.title,
            kind: document.kind,
            tags: document.tags,
            createdAt: document.createdAt,
            snippet: 'An invoice matching the search.',
          ),
        ),
    total: records.length,
  );
}
