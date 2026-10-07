import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/widgets/documents_workspace_toolbar.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_document_vocabulary_repository.dart';

void main() {
  void phoneViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
  }

  Rect panelRect(WidgetTester tester) => tester.getRect(
    find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first,
  );

  for (final rawRoute in [true, false]) {
    testWidgets(
      'large shared dialog clears phone system bars and keyboard on ${rawRoute ? 'raw' : 'Material'} route',
      (tester) async {
        phoneViewport(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      Widget form(BuildContext context) => AppDialog(
                        title: 'Large form',
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close form'),
                          ),
                        ],
                        child: const Column(
                          children: [
                            TextField(key: Key('dialogField')),
                            SizedBox(height: 1400),
                            Text('End of form'),
                          ],
                        ),
                      );

                      if (rawRoute) {
                        Navigator.of(context).push<void>(
                          RawDialogRoute<void>(
                            barrierDismissible: false,
                            pageBuilder: (context, _, _) => form(context),
                          ),
                        );
                      } else {
                        showDialog<void>(context: context, builder: form);
                      }
                    },
                    child: const Text('Open form'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open form'));
        await tester.pumpAndSettle();
        expect(panelRect(tester).top, 59 + 24);
        expect(panelRect(tester).bottom, 844 - 34 - 24);
        await tester.enterText(find.byKey(const Key('dialogField')), 'Draft');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        tester.view.padding = const FakeViewPadding(top: 59);
        await tester.pumpAndSettle();
        expect(panelRect(tester).top, 59 + 24);
        expect(panelRect(tester).bottom, 844 - 300 - 24);
        expect(find.text('Draft'), findsOneWidget);
        expect(find.text('Close form').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close form'));
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
      },
    );
  }

  testWidgets(
    'document filter close stays below the notch with keyboard open',
    (tester) async {
      phoneViewport(tester);
      final cubit = DocumentsCubit(
        FakeDocumentRepository(),
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      await cubit.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: DocumentsWorkspaceToolbar(
                  cubit: cubit,
                  vocabulary: FakeDocumentVocabularyRepository(count: 80),
                  libraryPicker: const Text('Personal'),
                  workspaceActions: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('documentFilters')));
      await tester.pumpAndSettle();
      final close = find.byKey(const Key('closeDocumentFilters'));
      expect(panelRect(tester).top, 59 + 12);
      expect(panelRect(tester).bottom, 844 - 34 - 12);
      expect(tester.getRect(close).top, greaterThanOrEqualTo(59));
      await tester.enterText(
        find.byKey(const Key('documentVocabularyQuery')),
        'option',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.padding = const FakeViewPadding(top: 59);
      await tester.pumpAndSettle();
      expect(panelRect(tester).top, 59 + 12);
      expect(panelRect(tester).bottom, 844 - 300 - 12);
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );
}
