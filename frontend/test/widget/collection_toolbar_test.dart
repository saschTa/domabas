import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/navigation_fonts.dart';

void main() {
  setUpAll(loadNavigationFonts);

  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'collection toolbar at $width and $scale keeps library right',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 420);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final term = TextEditingController(text: 'Insurance');
          addTearDown(term.dispose);
          var filtered = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: scale == 1 ? AppTheme.light() : AppTheme.dark(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: AppWorkspaceShell(
                groups: const [],
                selectedId: 'documents',
                onSelected: (_) {},
                accountLabel: 'person@example.test',
                onLogout: () {},
                libraryPicker: TextButton.icon(
                  key: const Key('testLibrary'),
                  onPressed: () {},
                  icon: const Icon(Icons.folder_outlined),
                  label: const Text(
                    'Home',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                toolbarBuilder: (context, library, workspaceActions) =>
                    AppCollectionToolbar(
                      search: AppSearchField(
                        controller: term,
                        fieldKey: const Key('testSearch'),
                        hintText: 'Search documents',
                      ),
                      actions: [
                        OutlinedButton.icon(
                          key: const Key('testFilters'),
                          onPressed: () => filtered = true,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Filters'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.sort_rounded),
                          label: const Text('Newest first'),
                        ),
                        IconButton(
                          onPressed: () {},
                          tooltip: 'Grid view',
                          icon: const Icon(Icons.grid_view_rounded),
                        ),
                      ],
                      libraryPicker: library,
                      workspaceActions: workspaceActions,
                      summary: const Text('3 active filters'),
                    ),
                child: ListView.builder(
                  itemCount: 60,
                  itemBuilder: (_, index) =>
                      ListTile(title: Text('Document $index')),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final primary = tester.getRect(
            find.byKey(const Key('collectionToolbarPrimary')),
          );
          final library = tester.getRect(
            find.byKey(const Key('collectionToolbarLibrary')),
          );
          final search = tester.getRect(find.byKey(const Key('testSearch')));
          expect(library.right, closeTo(primary.right, .1));
          expect(search.right, lessThan(library.left));
          expect(library.top, closeTo(search.top, .1));
          expect(
            tester.getSize(find.byKey(const Key('workspaceHeader'))).height,
            lessThanOrEqualTo(420 * .4),
          );
          await tester.ensureVisible(find.byKey(const Key('testFilters')));
          await tester.tap(find.byKey(const Key('testFilters')));
          await tester.pumpAndSettle();
          expect(filtered, isTrue);
          expect(term.text, 'Insurance');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('search submits and clears through feature callbacks', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var submitted = '';
    var completions = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AppSearchField(
            controller: controller,
            focusNode: focus,
            fieldKey: const Key('search'),
            submitKey: const Key('submit'),
            clearKey: const Key('clear'),
            onSubmitted: (value) => submitted = value,
            onEditingComplete: () => completions++,
            onClear: controller.clear,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('search')), 'Insurance');
    await tester.tap(find.byKey(const Key('submit')));
    expect(submitted, 'Insurance');
    await tester.tap(find.byKey(const Key('search')));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(completions, 1);
    await tester.pump();
    await tester.tap(find.byKey(const Key('clear')));
    expect(controller.text, isEmpty);
    await tester.pump();
    expect(find.byKey(const Key('clear')), findsNothing);
  });

  testWidgets('blocked search preserves an active composing value', (
    tester,
  ) async {
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'term',
        composing: TextRange(start: 0, end: 4),
      ),
    );
    addTearDown(controller.dispose);
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSearchField(
            controller: controller,
            submittingBlocked: true,
            submitKey: const Key('submit'),
            onSubmitted: (_) => submitted = true,
          ),
        ),
      ),
    );
    expect(
      tester.widget<IconButton>(find.byKey(const Key('submit'))).onPressed,
      isNull,
    );
    expect(controller.value.composing, const TextRange(start: 0, end: 4));
    expect(submitted, isFalse);
  });
}
