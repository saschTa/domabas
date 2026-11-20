import 'dart:ui' as ui;

import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const destinations = [
  GlacierDestination(
    id: 'documents',
    label: 'Documents',
    icon: Icons.description_outlined,
  ),
  GlacierDestination(
    id: 'settings',
    label: 'Settings',
    icon: Icons.settings_outlined,
    children: [
      GlacierDestination(
        id: 'members',
        label: 'Members',
        icon: Icons.people_outline,
      ),
      GlacierDestination(
        id: 'libraries',
        label: 'Libraries',
        icon: Icons.folder_outlined,
      ),
    ],
  ),
  GlacierDestination(
    id: 'admin',
    label: 'Administration',
    icon: Icons.admin_panel_settings_outlined,
    children: [
      GlacierDestination(
        id: 'users',
        label: 'System users',
        icon: Icons.people_outline,
      ),
    ],
  ),
];

void main() {
  testWidgets(
    'inline groups reveal below stable parents and preserve selection',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var selected = 'documents';
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return GlacierWorkspace(
                destinations: destinations,
                selected: selected,
                onSelected: (id) => setState(() => selected = id),
                onSearch: () {},
                libraryLabel: 'Personal',
                accountLabel: 'Alex',
                child: const Text('Workspace'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final settings = find.byKey(
        const ValueKey('navigation-trigger-settings'),
      );
      final admin = find.byKey(const ValueKey('navigation-trigger-admin'));
      final initialSettings = tester.getRect(settings);
      final initialAdmin = tester.getRect(admin);
      await tester.tap(settings);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final intermediateAdmin = tester.getRect(admin);
      expect(tester.getRect(settings), initialSettings);
      final triggerSemantics = tester.getSemantics(settings);
      final triggerData = triggerSemantics.getSemanticsData();
      expect(triggerData.label, 'Settings');
      expect(triggerData.flagsCollection.isButton, isTrue);
      expect(triggerData.flagsCollection.isExpanded, ui.Tristate.isTrue);
      expect(triggerData.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(triggerSemantics.rect.height, lessThan(80));
      expect(intermediateAdmin.top, greaterThan(initialAdmin.top));
      await tester.pumpAndSettle();
      expect(tester.getRect(admin).top, greaterThan(intermediateAdmin.top));
      expect(tester.getRect(settings), initialSettings);
      expect(
        find.ancestor(
          of: find.text('Members'),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Members'));
      await tester.pumpAndSettle();
      expect(selected, 'members');
      expect(find.text('Members'), findsOneWidget);
      await tester.tap(admin);
      await tester.pumpAndSettle();
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('System users'), findsOneWidget);
      await tester.tap(settings);
      await tester.pump();
      expect(find.text('Members').hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Members'), findsNothing);
      update(() {});
      await tester.pumpAndSettle();
      expect(find.text('Members'), findsNothing);
      expect(selected, 'members');
      update(() => selected = 'libraries');
      await tester.pumpAndSettle();
      expect(find.text('Libraries'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(600, 700));
      await tester.pumpAndSettle();
      expect(find.text('Libraries'), findsNothing);
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
      expect(find.text('Libraries'), findsOneWidget);
      expect(find.text('System users'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('inline keyboard disclosure returns child focus before hiding', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.dark(),
        home: GlacierWorkspace(
          destinations: destinations,
          selected: 'documents',
          onSelected: (_) {},
          onSearch: () {},
          libraryLabel: 'Personal',
          accountLabel: 'Alex',
          child: const Text('Workspace'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final settings = find.byKey(const ValueKey('navigation-trigger-settings'));
    tester.widget<InkWell>(settings).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<InkWell>(settings).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final first = find.byKey(const ValueKey('navigation-trigger-members'));
    expect(tester.widget<InkWell>(first).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<InkWell>(settings).focusNode!.hasFocus, isTrue);
    expect(first.hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(first, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(first, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'rail opens inline children and respects reduced motion $reduced',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: GlacierTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reduced,
                textScaler: TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: GlacierWorkspace(
              destinations: [
                for (var i = 0; i < 4; i++)
                  GlacierDestination(
                    id: 'main-$i',
                    label: 'Main $i',
                    icon: Icons.description_outlined,
                  ),
                ...destinations.skip(1),
              ],
              selected: 'members',
              onSelected: (_) {},
              onSearch: () {},
              libraryLabel: 'Personal',
              accountLabel: 'Alex',
              child: const Text('Workspace'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Members'), findsNothing);
        final settings = find.byKey(
          const ValueKey('navigation-trigger-settings'),
        );
        final railData = tester.getSemantics(settings).getSemanticsData();
        expect(railData.label, 'Settings');
        expect(railData.flagsCollection.isButton, isTrue);
        expect(railData.flagsCollection.isExpanded, ui.Tristate.isFalse);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(find.text('Members'), findsOneWidget);
        expect(find.text('Members').hitTestable(), findsOneWidget);
        expect(tester.getRect(settings).width, greaterThan(150));
        await tester.tap(settings);
        await tester.pump();
        if (reduced) expect(find.text('Members'), findsNothing);
        await tester.pumpAndSettle();
        expect(find.text('Members'), findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
  testWidgets(
    'dock keeps its bottom anchor through one-to-many and Escape returns focus',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var multiple = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: Stack(
                  children: [
                    Positioned(
                      left: 20,
                      bottom: 16,
                      child: GlacierActivityDock(
                        jobs: [
                          const GlacierActivityJob(
                            id: 'a',
                            title: 'Lease',
                            status: 'Waiting',
                          ),
                          if (multiple)
                            const GlacierActivityJob(
                              id: 'b',
                              title: 'Electricity',
                              status: 'Waiting',
                            ),
                        ],
                        onOpenActivity: () {},
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final token = find.byKey(const ValueKey('activity-dock-token'));
      final single = tester.getRect(token);
      update(() => multiple = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(token).bottom, closeTo(single.bottom, .1));
      await tester.pumpAndSettle();
      expect(tester.getRect(token).height, greaterThan(single.height));
      expect(tester.getRect(token).bottom, closeTo(single.bottom, .1));
      await tester.tap(token);
      await tester.pumpAndSettle();
      expect(find.text('View all activity'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('View all activity'), findsNothing);
      expect(tester.widget<InkWell>(token).focusNode!.hasFocus, isTrue);
      final tokenElement = tester.element(token);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      update(() => multiple = false);
      await tester.pump();
      expect(tester.getRect(token), single);
      expect(tester.element(token), same(tokenElement));
      expect(tester.widget<InkWell>(token).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dock hides zero and retains stale unknown progress without invented percentage',
    (tester) async {
      Future<void> render(
        List<GlacierActivityJob> jobs, {
        bool stale = false,
      }) => tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: GlacierActivityDock(
                jobs: jobs,
                stale: stale,
                onOpenActivity: () {},
              ),
            ),
          ),
        ),
      );
      await render(const []);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('activity-dock-token')), findsNothing);
      await render(const [
        GlacierActivityJob(
          id: 'a',
          title: 'Retained lease',
          status: 'Running',
          stage: 'Embeddings',
          running: true,
        ),
      ], stale: true);
      await tester.pumpAndSettle();
      expect(find.text('Retained lease'), findsOneWidget);
      expect(find.text('Last known activity · updates paused'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-dock-token')));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dock uses supplied known progress without shrinking the workspace',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: GlacierWorkspace(
            destinations: destinations,
            selected: 'documents',
            onSelected: (_) {},
            onSearch: () {},
            libraryLabel: 'Personal',
            accountLabel: 'Alex',
            activityDock: GlacierActivityDock(
              jobs: const [
                GlacierActivityJob(
                  id: 'a',
                  title: 'Lease',
                  status: 'Indexing',
                  progress: .42,
                ),
              ],
              onOpenActivity: () {},
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: TextButton(
                onPressed: () {},
                child: const Text('Last action'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final token = find.byKey(const ValueKey('activity-dock-token'));
      expect(
        tester.getRect(find.text('Last action')).bottom,
        greaterThan(tester.getRect(token).top),
      );
      expect(
        tester.getRect(find.text('Last action')).right,
        lessThan(tester.getRect(token).left),
      );
      final contentBeforeExpansion = tester.getRect(find.text('Last action'));
      await tester.tap(token);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Last action')), contentBeforeExpansion);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .42,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
