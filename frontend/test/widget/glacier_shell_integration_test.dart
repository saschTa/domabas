import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Glacier resize retains feature and toolbar state across layouts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light().copyWith(platform: TargetPlatform.macOS),
          home: AppWorkspaceShell(
            glacier: true,
            groups: [
              AppNavigationGroup(
                id: 'documents',
                label: 'Documents',
                icon: Icons.description,
                collapsible: false,
                items: const [
                  AppNavigationItem(
                    id: 'documents',
                    label: 'Documents',
                    icon: Icons.description,
                  ),
                ],
              ),
            ],
            selectedId: 'documents',
            onSelected: (_) {},
            libraryPicker: const SizedBox.shrink(),
            libraryLabel: 'Personal',
            accountLabel: 'alex@example.test',
            onLogout: () {},
            onSearch: () {},
            toolbarBuilder: (_, library, actions) =>
                const _GlacierStateProbe(label: 'Toolbar draft'),
            child: const _GlacierStateProbe(label: 'Feature draft'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final feature = find.byKey(const Key('Feature draft'));
      final toolbar = find.byKey(const Key('Toolbar draft'));
      final featureController = tester.widget<TextField>(feature).controller;
      final toolbarController = tester.widget<TextField>(toolbar).controller;
      await tester.enterText(feature, 'Retained record draft');
      await tester.enterText(toolbar, 'Retained filter draft');
      for (final size in [
        const Size(390, 844),
        const Size(768, 1024),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(feature).controller,
          same(featureController),
        );
        expect(
          tester.widget<TextField>(toolbar).controller,
          same(toolbarController),
        );
        expect(featureController!.text, 'Retained record draft');
        expect(toolbarController!.text, 'Retained filter draft');
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Glacier unavailable search does not gain a shortcut action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.light(),
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
          onSearch: null,
          libraryLabel: 'Restricted library',
          accountLabel: 'viewer@example.test',
          child: const Text('Limited access'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Limited access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _GlacierStateProbe extends StatefulWidget {
  const _GlacierStateProbe({required this.label});
  final String label;
  @override
  State<_GlacierStateProbe> createState() => _GlacierStateProbeState();
}

class _GlacierStateProbeState extends State<_GlacierStateProbe> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: TextField(
      key: Key(widget.label),
      controller: controller,
      decoration: InputDecoration(labelText: widget.label),
    ),
  );
}
