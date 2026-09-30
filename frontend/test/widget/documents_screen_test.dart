import 'dart:async';

import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

void main() {
  Widget workspace(DocumentsCubit model) => MaterialApp(
    theme: AppTheme.light(),
    home: Builder(
      builder: (context) => AppWorkspaceShell(
        groups: const [],
        selectedId: 'documents',
        onSelected: (_) {},
        libraryPicker: const Text('Personal library'),
        accountLabel: 'person@example.test',
        onLogout: () {},
        actions: [
          AppWorkspaceAction(
            id: 'newDocument',
            label: 'Create metadata',
            icon: Icons.note_add_outlined,
            onPressed: () => DocumentCreateAction.open(context, model),
          ),
        ],
        child: DocumentsScreen(cubit: model),
      ),
    ),
  );

  testWidgets('narrow app validates input, saves, and opens persisted detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeDocumentRepository();
    final model = DocumentsCubit(
      repository,
      capabilities: allDocumentCapabilities,
    );
    addTearDown(model.close);
    await model.load();
    await tester.pumpWidget(workspace(model));
    await tester.pumpAndSettle();
    expect(find.text('No documents yet'), findsOneWidget);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('newDocument')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveDocument')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a document title.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('documentTitle')), 'Insurance');
    await tester.enterText(
      find.byKey(const Key('documentDescription')),
      'Policy details',
    );
    await tester.tap(find.byKey(const Key('saveDocument')));
    await tester.pumpAndSettle();
    expect(find.text('Insurance'), findsOneWidget);
    await tester.ensureVisible(find.text('Insurance'));
    await tester.pumpAndSettle();
    expect(find.text('Insurance').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Insurance'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('documentDetails')), findsOneWidget);
    expect(repository.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'successful empty snapshot keeps its copy and count while replacement search waits or fails',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repository = _PendingSearchRepository();
      final model = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(model.close);
      await model.load();
      await tester.pumpWidget(workspace(model));
      await tester.pumpAndSettle();
      final count = tester
          .widget<Text>(find.byKey(const Key('documentCount')))
          .data;
      final pending = model.applySearch(
        DocumentSearchCriteria(query: 'new target'),
      );
      await tester.pump();
      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.text('Opening your library…'), findsNothing);
      expect(find.text('No matching documents'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('documentCount'))).data,
        count,
      );
      repository.response.completeError(
        const DocumentFailure(DocumentFailureKind.unavailable),
      );
      await pending;
      await tester.pumpAndSettle();
      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.text('Your library is unavailable'), findsNothing);
      repository.response = Completer<DocumentSearchPage>();
      final retry = model.retryCollection();
      repository.response.complete(DocumentSearchPage(items: [], total: 0));
      await retry;
      await tester.pumpAndSettle();
      expect(find.text('No matching documents'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('documentCount'))).data,
        '0 results',
      );
    },
  );

  testWidgets('error state offers retry and recovers to empty state', (
    tester,
  ) async {
    final repository = FakeDocumentRepository()
      ..failure = const DocumentFailure(DocumentFailureKind.unavailable);
    final model = DocumentsCubit(
      repository,
      capabilities: allDocumentCapabilities,
    );
    addTearDown(model.close);
    await model.load();
    await tester.pumpWidget(workspace(model));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Your library is unavailable'),
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('documentCollectionScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Your library is unavailable'), findsOneWidget);
    expect(find.text('No documents yet'), findsNothing);
    repository.failure = null;
    await tester.scrollUntilVisible(
      find.byTooltip('Retry'),
      -160,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('documentCollectionScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.byTooltip('Retry'));
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('No documents yet'),
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('documentCollectionScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('No documents yet'), findsOneWidget);
  });
}

final class _PendingSearchRepository extends FakeDocumentRepository {
  Completer<DocumentSearchPage> response = Completer<DocumentSearchPage>();
  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) => response.future;
}
