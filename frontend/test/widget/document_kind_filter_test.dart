import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/presentation/document/widgets/document_filter_dialog.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_document_vocabulary_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  late _KindSearchRepository repository;
  late DocumentsCubit documents;

  setUp(() {
    repository = _KindSearchRepository();
    documents = DocumentsCubit(
      repository,
      capabilities: allDocumentCapabilities,
    );
  });
  tearDown(() => documents.close());

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }
    await revealWorkspaceContent(
      tester,
      finder,
      scrollable: find
          .descendant(
            of: find.byKey(
              Key(
                find.byType(DocumentFilterDialog).evaluate().isNotEmpty
                    ? 'documentVocabularyScroll'
                    : 'documentCollectionScroll',
              ),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'quick types combine, clear independently and preserve the search term',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await documents.applySearch(
        DocumentSearchCriteria(query: 'invoice', tags: ['paid']),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DocumentsScreen(
              cubit: documents,
              vocabulary: FakeDocumentVocabularyRepository(),
            ),
          ),
        ),
      );
      await tap(tester, find.byKey(const Key('documentType-email')));
      expect(repository.requests.last.kinds, [DocumentKind.email]);
      expect(repository.requests.last.query, 'invoice');
      expect(repository.requests.last.tags, ['paid']);

      await tap(tester, find.byKey(const Key('documentType-email')));
      expect(repository.requests.last.kinds, isEmpty);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('documentType-all')))
            .selected,
        isTrue,
      );

      await tap(tester, find.byKey(const Key('documentType-document')));
      await tap(tester, find.byKey(const Key('documentType-letter')));
      expect(repository.requests.last.kinds, [
        DocumentKind.document,
        DocumentKind.letter,
      ]);
      await tap(tester, find.byTooltip('Remove Type: Documents, Letters'));
      expect(repository.requests.last.kinds, isEmpty);
      expect(repository.requests.last.tags, ['paid']);

      await tap(tester, find.byKey(const Key('documentType-email')));
      await tap(tester, find.text('Clear filters'));
      expect(repository.requests.last.kinds, isEmpty);
      expect(repository.requests.last.tags, isEmpty);
      expect(repository.requests.last.query, 'invoice');
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, scale) in [(320.0, 1.0), (390.0, 2.0)]) {
    testWidgets(
      'type filters and lookup remain reachable at width $width and scale $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 600);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await documents.applySearch(DocumentSearchCriteria(query: 'invoice'));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 600),
                textScaler: TextScaler.linear(scale),
              ),
              child: DocumentFilterDialog(
                documents: documents,
                repository: FakeDocumentVocabularyRepository(),
                isCurrent: () => true,
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.byKey(const Key('documentFilterType-email')));
        expect(repository.requests.last.kinds, [DocumentKind.email]);
        await tap(tester, find.byKey(const Key('documentFilter-sender')));
        await tester.ensureVisible(
          find.byKey(const Key('documentVocabularyQuery')),
        );
        await tester.enterText(
          find.byKey(const Key('documentVocabularyQuery')),
          'sender',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('closeDocumentFilters')).hitTestable(),
          findsOneWidget,
        );
        await tap(tester, find.text('Reset filters'));
        expect(repository.requests.last.kinds, isEmpty);
        expect(repository.requests.last.query, 'invoice');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _KindSearchRepository extends FakeDocumentRepository {
  final requests = <DocumentSearchCriteria>[];

  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async {
    requests.add(criteria);
    return DocumentSearchPage(items: const [], total: 0);
  }
}
