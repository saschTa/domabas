import 'dart:ui' show Tristate;

import 'package:domabas/ui/app_navigation_button.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/navigation_fonts.dart';

List<AppNavigationGroup> _groups({bool admin = true}) => [
  AppNavigationGroup(
    id: 'documents',
    label: 'Documents',
    icon: Icons.description_outlined,
    collapsible: false,
    items: const [
      AppNavigationItem(
        id: 'documents',
        label: 'Documents',
        icon: Icons.description_outlined,
        key: Key('documentsNavigation'),
      ),
    ],
  ),
  AppNavigationGroup(
    id: 'user-settings',
    label: 'User settings',
    compactLabel: 'Settings',
    icon: Icons.settings_outlined,
    items: const [
      AppNavigationItem(
        id: 'libraries',
        label: 'Libraries',
        icon: Icons.folder_outlined,
        key: Key('manageLibraries'),
      ),
      AppNavigationItem(
        id: 'password',
        label: 'Password',
        icon: Icons.password_outlined,
        key: Key('changePassword'),
      ),
    ],
  ),
  if (admin)
    AppNavigationGroup(
      id: 'admin-settings',
      label: 'Admin settings',
      compactLabel: 'Admin',
      icon: Icons.admin_panel_settings_outlined,
      items: const [
        AppNavigationItem(
          id: 'system-users',
          label: 'System users',
          icon: Icons.people_outline,
          key: Key('manageSystemUsers'),
        ),
      ],
    ),
];

class _Harness extends StatefulWidget {
  const _Harness({super.key, this.scale = 1, this.admin = true});
  final double scale;
  final bool admin;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final navigator = GlobalKey<NavigatorState>();
  final calls = <String>[];
  late List<AppNavigationGroup> groups = _groups(admin: widget.admin);
  String selected = 'documents';
  bool disableAnimations = false;
  bool showShell = true;
  List<String>? mobilePrimaryGroupIds;
  List<AppNavigationGroup>? mobileGroups;
  double keyboardInset = 0;

  void change(VoidCallback action) => setState(action);

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(widget.scale),
        disableAnimations: disableAnimations,
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: child!,
    ),
    home: showShell
        ? AppWorkspaceShell(
            groups: groups,
            mobileGroups: mobileGroups,
            mobilePrimaryGroupIds: mobilePrimaryGroupIds,
            selectedId: selected,
            onSelected: (value) => setState(() {
              calls.add(value);
              selected = value;
            }),
            libraryPicker: const Text('Test library'),
            accountLabel: 'person@example.test',
            onLogout: () {},
            child: Center(child: Text('Page: $selected')),
          )
        : const Scaffold(body: Text('Replacement session')),
  );
}

void main() {
  setUpAll(loadNavigationFonts);
  Future<GlobalKey<_HarnessState>> mount(
    WidgetTester tester, {
    double width = 390,
    double height = 844,
    double scale = 1,
    bool admin = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key, scale: scale, admin: admin));
    await tester.pumpAndSettle();
    return key;
  }

  Finder button(String key) => find.byKey(Key(key));
  AppNavigationButton control(WidgetTester tester, String key) =>
      tester.widget<AppNavigationButton>(button(key));
  Future<void> open(
    WidgetTester tester, {
    String group = 'user-settings',
  }) async {
    await tester.ensureVisible(button('navigation-$group'));
    await tester.tap(button('navigation-$group'));
    await tester.pumpAndSettle();
  }

  Future<GlobalKey<_HarnessState>> mountMobileNavigation(
    WidgetTester tester, {
    bool admin = true,
    double scale = 1,
    double width = 390,
  }) async {
    final key = await mount(tester, admin: admin, scale: scale, width: width);
    key.currentState!.change(() {
      key.currentState!.mobilePrimaryGroupIds = [
        'invoices',
        'scanner',
        'documents',
        'chat',
      ];
      key.currentState!.groups = [
        ..._groups(admin: admin),
        for (final (id, label) in [
          ('invoices', 'Invoices'),
          ('jobs', 'Jobs'),
          ('chat', 'AI chat'),
        ])
          AppNavigationGroup(
            id: id,
            label: label,
            icon: Icons.description_outlined,
            collapsible: false,
            items: [
              AppNavigationItem(
                id: id,
                label: label,
                icon: Icons.description_outlined,
                key: Key('${id}Navigation'),
              ),
            ],
          ),
      ];
      key.currentState!.mobileGroups = [
        ...key.currentState!.groups,
        AppNavigationGroup(
          id: 'scanner',
          label: 'Scanner',
          icon: Icons.document_scanner_outlined,
          collapsible: false,
          items: const [
            AppNavigationItem(
              id: 'scanner',
              label: 'Scanner',
              icon: Icons.document_scanner_outlined,
              key: Key('scannerNavigation'),
            ),
          ],
        ),
      ];
    });
    await tester.pumpAndSettle();
    return key;
  }

  for (final admin in [false, true]) {
    testWidgets('five mobile slots stay compact with admin $admin', (
      tester,
    ) async {
      final key = await mountMobileNavigation(tester, admin: admin);
      expect(button('workspaceNotchedNavigation'), findsOneWidget);
      expect(button('workspaceNavigationFallback'), findsNothing);
      expect(tester.getSize(button('workspaceBottomNavigation')).height, 104);
      expect(tester.getCenter(button('navigationDocumentsCircle')).dx, 195);
      final slots = [
        'invoicesNavigation',
        'scannerNavigation',
        'documentsNavigation',
        'chatNavigation',
        'navigation-more',
      ];
      for (var index = 0; index < slots.length; index++) {
        expect(button(slots[index]).hitTestable(), findsOneWidget);
        expect(
          tester.getSize(button(slots[index])).width,
          greaterThanOrEqualTo(48),
        );
        if (index > 0) {
          expect(
            tester.getCenter(button(slots[index])).dx,
            greaterThan(tester.getCenter(button(slots[index - 1])).dx),
          );
        }
      }
      expect(button('jobsNavigation'), findsNothing);
      await open(tester, group: 'more');
      expect(button('workspaceMoreDrawer'), findsOneWidget);
      expect(button('jobsNavigation'), findsOneWidget);
      expect(
        button('manageSystemUsers'),
        admin ? findsOneWidget : findsNothing,
      );
      expect(key.currentState!.calls, isEmpty);
      await tester.tap(button('changePassword'));
      await tester.pumpAndSettle();
      expect(find.text('Page: password'), findsOneWidget);
      expect(control(tester, slots.last).selected, isTrue);
      expect(button('workspaceMoreDrawer'), findsNothing);
    });
  }

  testWidgets(
    'More includes future destinations and dismisses on resize and permission changes',
    (tester) async {
      final key = await mountMobileNavigation(tester);
      key.currentState!.change(
        () => key.currentState!.mobileGroups!.add(
          AppNavigationGroup(
            id: 'reports',
            label: 'Reports',
            icon: Icons.analytics_outlined,
            collapsible: false,
            items: const [
              AppNavigationItem(
                id: 'reports',
                label: 'Reports',
                icon: Icons.analytics_outlined,
                key: Key('reportsNavigation'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(button('reportsNavigation'), findsNothing);
      await open(tester, group: 'more');
      await tester.ensureVisible(button('reportsNavigation'));
      await tester.tap(button('reportsNavigation'));
      await tester.pumpAndSettle();
      expect(key.currentState!.selected, 'reports');
      expect(control(tester, 'navigation-more').selected, isTrue);
      await open(tester, group: 'more');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(button('workspaceMoreDrawer'), findsNothing);
      expect(control(tester, 'navigation-more').focusNode!.hasFocus, isTrue);
      await open(tester, group: 'more');
      final stale = control(tester, 'manageSystemUsers').onPressed;
      key.currentState!.change(
        () => key.currentState!.mobileGroups!.removeWhere(
          (group) => group.id == 'admin-settings',
        ),
      );
      await tester.pumpAndSettle();
      stale();
      await tester.pumpAndSettle();
      expect(button('workspaceMoreDrawer'), findsNothing);
      expect(key.currentState!.selected, 'reports');
      await open(tester, group: 'more');
      tester.view.physicalSize = const Size(900, 844);
      await tester.pumpAndSettle();
      expect(button('workspaceMoreDrawer'), findsNothing);
      expect(button('workspaceBottomNavigation'), findsNothing);
      expect(button('reportsNavigation'), findsNothing);
      expect(button('scannerNavigation'), findsNothing);
      expect(button('jobsNavigation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone bar clears the home indicator with a bottom margin', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await mountMobileNavigation(tester);
    final bar = tester.getRect(button('workspaceNotchedNavigation'));
    expect(bar.bottom, 844 - 34 - 8);
    expect(bar.left, 12);
    expect(bar.right, 390 - 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More remains reachable at large text and narrow width', (
    tester,
  ) async {
    await mountMobileNavigation(tester, width: 320, scale: 2);
    expect(button('workspaceNavigationFallback'), findsOneWidget);
    await open(tester, group: 'more');
    await tester.ensureVisible(button('manageSystemUsers'));
    await tester.tap(button('manageSystemUsers'));
    await tester.pumpAndSettle();
    expect(find.text('Page: system-users'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile actions reject stale callbacks after removal and resize',
    (tester) async {
      final key = await mountMobileNavigation(tester, admin: false);
      final scanner = control(tester, 'scannerNavigation').onPressed;
      scanner();
      await tester.pumpAndSettle();
      expect(key.currentState!.calls, ['scanner']);
      key.currentState!.change(
        () => key.currentState!.mobileGroups!.removeWhere(
          (group) => group.id == 'scanner',
        ),
      );
      await tester.pumpAndSettle();
      scanner();
      expect(key.currentState!.calls, ['scanner']);
      expect(button('jobsNavigation'), findsNothing);
      await open(tester, group: 'more');
      await tester.ensureVisible(button('jobsNavigation'));
      await tester.tap(button('jobsNavigation'));
      await tester.pumpAndSettle();
      expect(key.currentState!.selected, 'jobs');
      expect(control(tester, 'navigation-more').selected, isTrue);
      for (final width in [900.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        scanner();
        expect(key.currentState!.calls, ['scanner', 'jobs']);
        expect(button('scannerNavigation'), findsNothing);
        expect(button('jobsNavigation'), findsOneWidget);
        expect(button('navigation-more'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 900.0]) {
    testWidgets(
      'width $width exposes one button with each exact semantic name and 48px targets',
      (tester) async {
        await mount(tester, width: width);
        for (final (key, label) in [
          ('documentsNavigation', 'Documents'),
          ('navigation-user-settings', 'User settings'),
          ('navigation-admin-settings', 'Admin settings'),
        ]) {
          final node = tester.getSemantics(button(key));
          expect(node.label, label);
          expect(node.flagsCollection.isButton, isTrue);
          expect(tester.getSize(button(key)).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(button(key)).height, greaterThanOrEqualTo(48));
          var buttons = 0;
          void count(SemanticsNode child) {
            if (child.flagsCollection.isButton) buttons++;
            child.visitChildren((next) {
              count(next);
              return true;
            });
          }

          count(node);
          expect(buttons, 1);
        }
      },
    );
  }

  testWidgets(
    'opening and cancelling settings changes expanded state without selecting its parent',
    (tester) async {
      final key = await mount(tester);
      expect(
        tester
            .getSemantics(button('documentsNavigation'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      final trigger = control(tester, 'navigation-user-settings').onPressed;
      await open(tester);
      trigger();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('closeNavigationChooser')), findsOneWidget);
      expect(control(tester, 'navigation-user-settings').selected, isFalse);
      expect(control(tester, 'navigation-user-settings').expanded, isTrue);
      expect(key.currentState!.calls, isEmpty);
      await tester.tap(button('closeNavigationChooser'));
      await tester.pumpAndSettle();
      expect(find.text('Page: documents'), findsOneWidget);
      expect(control(tester, 'navigation-user-settings').expanded, isFalse);
      await open(tester);
      await tester.tap(button('changePassword'));
      await tester.pumpAndSettle();
      expect(find.text('Page: password'), findsOneWidget);
      expect(
        tester
            .getSemantics(button('navigation-user-settings'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(button('documentsNavigation'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      expect(key.currentState!.calls, ['password']);
    },
  );

  for (final activation in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
  ]) {
    testWidgets(
      '${activation.keyLabel} opens settings and Escape restores its trigger focus',
      (tester) async {
        final key = await mount(tester);
        final focus = control(tester, 'navigation-user-settings').focusNode!;
        focus.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(activation);
        await tester.pumpAndSettle();
        expect(button('manageLibraries'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(button('manageLibraries'), findsNothing);
        expect(focus.hasFocus, isTrue);
        expect(key.currentState!.calls, isEmpty);
        expect(find.text('Page: documents'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [390.0, 900.0]) {
    testWidgets(
      'width $width invalidated chooser cannot remove a newer route',
      (tester) async {
        final key = await mount(tester, width: width);
        final state = key.currentState!;
        final oldTrigger = control(
          tester,
          'navigation-user-settings',
        ).onPressed;
        await open(tester);
        VoidCallback? oldLeaf;
        VoidCallback? oldClose;
        VoidCallback? oldEscape;
        if (width < 600) {
          oldLeaf = control(tester, 'manageLibraries').onPressed;
          oldClose = tester
              .widget<IconButton>(button('closeNavigationChooser'))
              .onPressed;
          final shortcuts = tester.widget<CallbackShortcuts>(
            find
                .ancestor(
                  of: button('closeNavigationChooser'),
                  matching: find.byType(CallbackShortcuts),
                )
                .first,
          );
          oldEscape = shortcuts.bindings.values.single;
        }
        state.navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Newer protected route')),
          ),
        );
        await tester.pumpAndSettle();
        oldLeaf?.call();
        oldClose?.call();
        oldEscape?.call();
        await tester.pumpAndSettle();
        expect(find.text('Newer protected route'), findsOneWidget);
        state.change(() => state.groups = [state.groups.first]);
        await tester.pumpAndSettle();
        oldLeaf?.call();
        oldClose?.call();
        oldEscape?.call();
        oldTrigger();
        await tester.pumpAndSettle();
        expect(find.text('Newer protected route'), findsOneWidget);
        expect(state.calls, isEmpty);
        state.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('Page: documents'), findsOneWidget);
        expect(button('manageLibraries'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'retained chooser callbacks after session disposal cannot act on the replacement route',
    (tester) async {
      final key = await mount(tester);
      final state = key.currentState!;
      final oldTrigger = control(tester, 'navigation-user-settings').onPressed;
      await open(tester);
      final oldLeaf = control(tester, 'manageLibraries').onPressed;
      final oldClose = tester
          .widget<IconButton>(button('closeNavigationChooser'))
          .onPressed!;
      final oldEscape = tester
          .widget<CallbackShortcuts>(
            find
                .ancestor(
                  of: button('closeNavigationChooser'),
                  matching: find.byType(CallbackShortcuts),
                )
                .first,
          )
          .bindings
          .values
          .single;
      state.change(() => state.showShell = false);
      await tester.pumpAndSettle();
      state.navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Replacement detail')),
        ),
      );
      await tester.pumpAndSettle();
      oldLeaf();
      oldClose();
      oldEscape();
      oldTrigger();
      await tester.pumpAndSettle();
      expect(find.text('Replacement detail'), findsOneWidget);
      expect(state.calls, isEmpty);
      state.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Replacement session'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open chooser resize across both breakpoints preserves its leaf and rejects old triggers',
    (tester) async {
      final key = await mount(tester, width: 599);
      await open(tester);
      await tester.tap(button('manageLibraries'));
      await tester.pumpAndSettle();
      for (final width in [600.0, 1099.0, 1100.0, 599.0]) {
        final oldTrigger = control(
          tester,
          'navigation-user-settings',
        ).onPressed;
        if (tester.view.physicalSize.width < 1100) await open(tester);
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        oldTrigger();
        await tester.pumpAndSettle();
        if (width == 1099) {
          expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        expect(find.text('Page: libraries'), findsOneWidget);
        expect(button('closeNavigationChooser'), findsNothing);
        expect(find.byType(PopupMenuItem<String>), findsNothing);
        expect(key.currentState!.calls, ['libraries']);
        expect(control(tester, 'navigation-user-settings').selected, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final (width, flag) in [
    (390.0, 'disableAnimations'),
    (390.0, 'reduceMotion'),
    (900.0, 'disableAnimations'),
    (900.0, 'reduceMotion'),
  ]) {
    testWidgets(
      '$flag alone cancels an open $width chooser and subsequent presentation has no transition',
      (tester) async {
        final key = await mount(tester, width: width);
        final state = key.currentState!;
        await open(tester);
        expect(button('manageLibraries'), findsOneWidget);
        if (flag == 'disableAnimations') {
          state.change(() => state.disableAnimations = true);
        } else {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(button('manageLibraries'), findsNothing);
        expect(state.selected, 'documents');
        expect(state.calls, isEmpty);
        await tester.tap(button('navigation-user-settings'));
        await tester.pump();
        await tester.pump();
        expect(button('manageLibraries'), findsOneWidget);
        final route = ModalRoute.of(tester.element(button('manageLibraries')))!;
        expect(route.animation!.status, AnimationStatus.completed);
        await tester.tap(button('manageLibraries'));
        await tester.pump();
        await tester.pump();
        expect(route.isActive, isFalse);
        expect(find.text('Page: libraries'), findsOneWidget);
        expect(state.calls, ['libraries']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'height-only resize after a detail route preserves accessible geometry and activation',
    (tester) async {
      final key = await mount(tester, width: 320, height: 640, admin: false);
      final state = key.currentState!;
      state.navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Full screen detail')),
        ),
      );
      await tester.pumpAndSettle();
      state.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      for (final height in [320.0, 640.0]) {
        tester.view.physicalSize = Size(320, height);
        await tester.pumpAndSettle();
        final settings = button('navigation-user-settings');
        final node = tester.getSemantics(settings);
        var rect = node.rect;
        SemanticsNode? ancestor = node;
        while (ancestor != null) {
          if (ancestor.transform case final transform?) {
            rect = MatrixUtils.transformRect(transform, rect);
          }
          ancestor = ancestor.parent;
        }
        expect(rect, tester.getRect(settings));
        expect(rect.bottom, lessThanOrEqualTo(height));
        expect(settings.hitTestable(), findsOneWidget);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(button('manageLibraries'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          control(tester, 'navigation-user-settings').focusNode!.hasFocus,
          isTrue,
        );
        expect(state.calls, isEmpty);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final flag in ['disableAnimations', 'reduceMotion']) {
    void enableMotionPreference(WidgetTester tester, _HarnessState state) {
      if (flag == 'disableAnimations') {
        state.change(() => state.disableAnimations = true);
      } else {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(reduceMotion: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
      }
    }

    testWidgets(
      '$flag settles an active desktop chevron and preserves trigger focus',
      (tester) async {
        final key = await mount(tester, width: 1200);
        final trigger = button('navigation-user-settings');
        final focus = control(tester, 'navigation-user-settings').focusNode!;
        focus.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        Matrix4 chevronTransform() => tester
            .renderObject<RenderBox>(
              find.descendant(
                of: trigger,
                matching: find.byIcon(Icons.expand_more),
              ),
            )
            .getTransformTo(tester.renderObject(trigger));
        expect(chevronTransform().entry(0, 0), lessThan(1));
        enableMotionPreference(tester, key.currentState!);
        await tester.pump();
        await tester.pump();
        expect(chevronTransform().entry(0, 0), closeTo(1, 0.000001));
        expect(chevronTransform().entry(0, 1), closeTo(0, 0.000001));
        expect(focus.hasFocus, isTrue);
        expect(button('manageLibraries'), findsNothing);
        expect(find.text('Page: documents'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$flag settles the moving selection marker without changing the fixed circle or losing focus',
      (tester) async {
        final key = await mount(tester);
        await open(tester);
        await tester.tap(button('manageLibraries'));
        await tester.pumpAndSettle();
        final documents = button('documentsNavigation');
        final focus = control(tester, 'documentsNavigation').focusNode!;
        focus.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        final marker = find.byKey(const Key('navigation-marker-documents'));
        Color? color() =>
            (tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: marker,
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration)
                .color;
        final primary = Theme.of(tester.element(documents)).colorScheme.primary;
        expect(color(), isNot(primary));
        expect(
          (tester
                      .widget<Container>(
                        find.byKey(const Key('navigationDocumentsCircle')),
                      )
                      .decoration
                  as BoxDecoration)
              .color,
          primary,
        );
        enableMotionPreference(tester, key.currentState!);
        await tester.pump();
        await tester.pump();
        expect(color(), primary);
        expect(focus.hasFocus, isTrue);
        expect(find.text('Page: documents'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$flag settles desktop hover immediately while preserving target and selected feedback',
      (tester) async {
        final key = await mount(tester, width: 1200);
        final leaf = button('manageLibraries');
        final initialRect = tester.getRect(leaf);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1190, 800));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(leaf));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        if (flag == 'disableAnimations') {
          key.currentState!.change(
            () => key.currentState!.disableAnimations = true,
          );
        } else {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        await tester.pump();
        await tester.pump();
        BoxDecoration decoration() =>
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: leaf,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(
          decoration().color,
          Theme.of(tester.element(leaf)).scaffoldBackgroundColor,
        );
        expect(decoration().boxShadow, isEmpty);
        expect(
          (decoration().border! as Border).top.color,
          Theme.of(tester.element(leaf)).colorScheme.primary,
        );
        expect(tester.getRect(leaf), initialRect);
        await tester.tap(leaf);
        await tester.pumpAndSettle();
        await mouse.moveTo(const Offset(1190, 800));
        await tester.pumpAndSettle();
        expect(
          decoration().color,
          Theme.of(tester.element(leaf)).colorScheme.onSurface,
        );
        expect(find.text('Page: libraries'), findsOneWidget);
        expect((decoration().border! as Border).top.color.a, 0);
        expect(tester.getRect(leaf), initialRect);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'keyboard inset hides and restores bottom navigation without losing the selected leaf',
    (tester) async {
      final key = await mount(tester);
      final state = key.currentState!;
      await open(tester);
      await tester.tap(button('changePassword'));
      await tester.pumpAndSettle();
      state.change(() => state.keyboardInset = 300);
      await tester.pumpAndSettle();
      expect(button('workspaceBottomNavigation'), findsNothing);
      expect(find.text('Page: password'), findsOneWidget);
      state.change(() => state.keyboardInset = 0);
      await tester.pumpAndSettle();
      expect(button('workspaceBottomNavigation'), findsOneWidget);
      expect(control(tester, 'navigation-user-settings').selected, isTrue);
      expect(state.calls, ['password']);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, admin) in [(320.0, false), (320.0, true), (390.0, true)]) {
    testWidgets(
      'all mobile labels retain 2x scaling and all groups activate at $width, admin $admin',
      (tester) async {
        await mount(tester, width: width, scale: 2, admin: admin);
        for (final label in ['Documents', 'Settings', if (admin) 'Admin']) {
          final text = find.text(label);
          expect(text, findsOneWidget);
          final context = tester.element(text);
          final widget = tester.widget<Text>(text);
          expect(
            MediaQuery.textScalerOf(context).scale(widget.style!.fontSize!),
            widget.style!.fontSize! * 2,
          );
          expect(widget.maxLines, isNull);
          expect(widget.overflow, isNull);
        }
        await open(tester);
        await tester.ensureVisible(button('changePassword'));
        await tester.tap(button('changePassword'));
        await tester.pumpAndSettle();
        expect(find.text('Page: password'), findsOneWidget);
        if (admin) {
          await open(tester, group: 'admin-settings');
          await tester.tap(button('manageSystemUsers'));
          await tester.pumpAndSettle();
          expect(find.text('Page: system-users'), findsOneWidget);
        }
        await tester.ensureVisible(button('documentsNavigation'));
        await tester.tap(button('documentsNavigation'));
        await tester.pumpAndSettle();
        expect(find.text('Page: documents'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
