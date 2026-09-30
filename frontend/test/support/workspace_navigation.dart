import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

export '../../integration_test/workspace_actions.dart';

Future<void> revealWorkspaceContent(
  WidgetTester tester,
  Finder target, {
  required Finder scrollable,
  int maxAttempts = 100,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    var viewport = tester.getRect(scrollable);
    final navigation = find.byKey(const Key('workspaceBottomNavigation'));
    if (navigation.evaluate().isNotEmpty) {
      viewport = viewport.intersect(
        Rect.fromLTRB(
          viewport.left,
          viewport.top,
          viewport.right,
          tester.getRect(navigation).top,
        ),
      );
    }
    expect(viewport.height, greaterThan(0));
    final delta = target.evaluate().isEmpty
        ? -250.0
        : (viewport.center.dy - tester.getRect(target).center.dy).clamp(
            -250.0,
            250.0,
          );
    await tester.dragFrom(viewport.center, Offset(0, delta));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> navigateWorkspace(
  WidgetTester tester,
  String key, {
  String group = 'User settings',
}) async {
  final destination = find.byKey(Key(key));
  if (destination.evaluate().isEmpty &&
      find
          .byKey(const Key('workspaceBottomNavigation'))
          .evaluate()
          .isNotEmpty) {
    final trigger = find.byKey(
      Key(
        find.byKey(const Key('navigation-more')).evaluate().isNotEmpty
            ? 'navigation-more'
            : group == 'Admin settings'
            ? 'navigation-admin-settings'
            : 'navigation-user-settings',
      ),
    );
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  } else if (destination.evaluate().isEmpty) {
    await tester.tap(find.byTooltip(group));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(destination);
  await tester.tap(destination);
  await tester.pumpAndSettle();
}
