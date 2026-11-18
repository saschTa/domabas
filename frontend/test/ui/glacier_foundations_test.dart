import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('intermediate rail expands nested destinations', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.light(),
        home: GlacierWorkspace(
          destinations: const [
            GlacierDestination(
              id: 'settings',
              label: 'Settings',
              icon: Icons.settings,
              children: [
                GlacierDestination(
                  id: 'members',
                  label: 'Members',
                  icon: Icons.people,
                ),
              ],
            ),
          ],
          selected: 'documents',
          onSelected: (id) => selected = id,
          onSearch: () {},
          libraryLabel: 'Personal',
          accountLabel: 'Alex',
          child: const Text('Content'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Members'));
    expect(selected, 'members');
    expect(tester.takeException(), isNull);
  });
  testWidgets('rich choice exposes mixed state and one keyboard action', (
    tester,
  ) async {
    bool? changed;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.light(),
        home: Scaffold(
          body: GlacierChoice(
            label: 'Include invoices',
            selected: null,
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(GlacierChoice)),
      matchesSemantics(
        label: 'Include invoices',
        hasCheckedState: true,
        isCheckStateMixed: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(changed, isTrue);
    semantics.dispose();
  });
  testWidgets(
    'sidebar hides utilities when collapsed and retains search shortcut',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var searches = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.dark(),
          home: GlacierWorkspace(
            destinations: const [
              GlacierDestination(
                id: 'documents',
                label: 'Documents',
                icon: Icons.description,
              ),
            ],
            selected: 'documents',
            onSelected: (_) {},
            onSearch: () => searches++,
            libraryLabel: 'Personal library',
            accountLabel: 'Alex',
            onLibrary: () {},
            onActivity: () {},
            onAppearance: () {},
            child: const Text('Library records'),
          ),
        ),
      );
      expect(find.byTooltip('Appearance'), findsOneWidget);
      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Appearance'), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(searches, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reduced transparency removes backdrop filters', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.light(opaque: true),
        home: const Scaffold(
          body: GlacierSurface(child: Text('Readable solid surface')),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
