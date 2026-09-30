import 'dart:async';

import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness extends StatefulWidget {
  const _Harness({super.key, this.scale = 1, this.dark = false});
  final double scale;
  final bool dark;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final navigator = GlobalKey<NavigatorState>();
  String owner = 'documents';
  bool enabled = true, allowed = true, visible = true;
  String status = 'Connected';
  int activations = 0;
  Future<void> Function()? onActivate;
  void change(VoidCallback update) => setState(update);

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    theme: widget.dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(widget.scale)),
      child: child!,
    ),
    home: visible
        ? AppWorkspaceShell(
            groups: const [],
            selectedId: owner,
            onSelected: (_) {},
            libraryPicker: TextButton(
              onPressed: () {},
              child: const Text(
                'A very long library name that must stay on a single line',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            accountLabel: 'person@example.test',
            onLogout: () {},
            actions: [
              if (allowed)
                AppWorkspaceAction(
                  id: 'uploadFiles',
                  label: 'Upload files',
                  icon: Icons.upload_file,
                  onPressed: enabled
                      ? () async {
                          activations++;
                          await onActivate?.call();
                        }
                      : null,
                ),
              AppWorkspaceAction(
                id: 'newDocument',
                label: 'Create metadata',
                icon: Icons.note_add_outlined,
                onPressed: () async {},
              ),
              AppWorkspaceAction(
                id: 'viewUploads',
                label: 'View uploads',
                icon: Icons.receipt_long_outlined,
                onPressed: () async {},
              ),
            ],
            utilityActions: [
              AppWorkspaceAction(
                id: 'appearance-action',
                label: 'Appearance',
                icon: Icons.brightness_auto,
                onPressed: () async {},
              ),
              AppWorkspaceAction(
                id: 'liveUpdatesStatus',
                label: 'Live updates',
                icon: Icons.cloud_done,
                detail: status,
                onPressed: () async {},
              ),
              AppWorkspaceAction(
                id: 'personal-activity',
                label: 'Your jobs',
                icon: Icons.work_history,
                badge: '3',
                onPressed: () async {},
              ),
            ],
            child: const Center(child: Text('Collection')),
          )
        : const Scaffold(body: Text('Replacement session')),
  );
}

void main() {
  Future<GlobalKey<_HarnessState>> mount(
    WidgetTester tester, {
    double width = 320,
    double height = 740,
    double scale = 1,
    bool dark = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key, scale: scale, dark: dark));
    await tester.pumpAndSettle();
    return key;
  }

  Future<void> more(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 900.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'one complete header row at $width / $scale in a short window',
        (tester) async {
          await mount(
            tester,
            width: width,
            height: 320,
            scale: scale,
            dark: scale == 2,
          );
          final header = tester.getRect(
            find.byKey(const Key('workspaceHeader')),
          );
          final row = tester.getRect(
            find.byKey(const Key('workspaceHeaderRow')),
          );
          expect(header.height, lessThanOrEqualTo(80));
          final controls = find.descendant(
            of: find.byKey(const Key('workspaceHeaderRow')),
            matching: find.byWidgetPredicate(
              (value) =>
                  value is IconButton ||
                  value is TextButton ||
                  value is FilledButton,
            ),
          );
          Rect? previous;
          for (final element in controls.evaluate()) {
            final bounds = tester.getRect(find.byWidget(element.widget));
            expect(bounds.width, greaterThanOrEqualTo(48));
            expect(bounds.height, greaterThanOrEqualTo(48));
            expect(bounds.center.dy, closeTo(row.center.dy, .1));
            expect(header.contains(bounds.topLeft), isTrue);
            expect(
              header.contains(bounds.bottomRight - const Offset(.1, .1)),
              isTrue,
            );
            if (previous != null) {
              expect(bounds.left, greaterThanOrEqualTo(previous.right));
            }
            previous = bounds;
          }
        },
      );
    }
  }

  testWidgets(
    'open chooser reflects busy/status updates and invokes only current enabled action',
    (tester) async {
      final key = await mount(tester);
      await more(tester);
      key.currentState!.change(() {
        key.currentState!.enabled = false;
        key.currentState!.status = 'Reconnecting';
      });
      await tester.pumpAndSettle();
      expect(find.text('Reconnecting'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('uploadFiles')))
            .onPressed,
        isNull,
      );
      key.currentState!.change(() => key.currentState!.enabled = true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('uploadFiles')));
      expect(key.currentState!.activations, 1);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close actions'), findsNothing);
    },
  );

  for (final mutation in ['permission', 'destination', 'scope', 'resize']) {
    testWidgets(
      '$mutation invalidates exact chooser and fences saved callbacks',
      (tester) async {
        final key = await mount(tester);
        await more(tester);
        final saved = tester
            .widget<TextButton>(find.byKey(const Key('uploadFiles')))
            .onPressed!;
        switch (mutation) {
          case 'permission':
            key.currentState!.change(() => key.currentState!.allowed = false);
          case 'destination':
            key.currentState!.change(
              () => key.currentState!.owner = 'libraries',
            );
          case 'scope':
            key.currentState!.change(() => key.currentState!.visible = false);
          case 'resize':
            tester.view.physicalSize = const Size(900, 740);
        }
        await tester.pumpAndSettle();
        saved();
        await tester.pumpAndSettle();
        expect(key.currentState!.activations, 0);
        expect(find.byTooltip('Close actions'), findsNothing);
      },
    );
  }

  testWidgets(
    'covered chooser cannot act or pop a newer route; Escape restores trigger focus',
    (tester) async {
      final key = await mount(tester);
      await more(tester);
      final saved = tester
          .widget<TextButton>(find.byKey(const Key('uploadFiles')))
          .onPressed!;
      final route = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Newer route')),
      );
      unawaited(key.currentState!.navigator.currentState!.push(route));
      await tester.pumpAndSettle();
      saved();
      await tester.pumpAndSettle();
      expect(find.text('Newer route'), findsOneWidget);
      expect(key.currentState!.activations, 0);
      key.currentState!.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final trigger = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const Key('workspaceMore')),
          matching: find.byType(IconButton),
        ),
      );
      expect(trigger.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets('activation keeps nested dialog focus until action completes', (
    tester,
  ) async {
    final key = await mount(tester);
    key.currentState!.onActivate = () => showDialog<void>(
      context: key.currentState!.navigator.currentContext!,
      builder: (_) => const AlertDialog(
        title: Text('Nested dialog'),
        content: TextField(autofocus: true),
      ),
    );
    await more(tester);
    await tester.tap(find.byKey(const Key('uploadFiles')));
    await tester.pumpAndSettle();
    expect(find.text('Nested dialog'), findsOneWidget);
    expect(find.byTooltip('Close actions'), findsNothing);
    expect(FocusManager.instance.primaryFocus!.context, isNotNull);
    final trigger = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('workspaceMore')),
        matching: find.byType(IconButton),
      ),
    );
    expect(trigger.focusNode!.hasFocus, isFalse);
    key.currentState!.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(trigger.focusNode!.hasFocus, isTrue);
    expect(key.currentState!.activations, 1);
  });
}
