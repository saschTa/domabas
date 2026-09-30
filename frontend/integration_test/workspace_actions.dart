import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitForWorkspaceWidget(
  WidgetTester tester,
  Finder finder, {
  bool present = true,
}) async {
  final count = present ? 1 : 0;
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (finder.evaluate().length != count &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull);
  expect(finder, present ? findsOneWidget : findsNothing);
}

Future<void> revealWorkspaceAction(WidgetTester tester, String key) async {
  final action = find.byKey(Key(key));
  if (action.evaluate().isEmpty) {
    final utility = const {
      'appearance-action',
      'liveUpdatesStatus',
      'personal-activity',
      'logout',
    }.contains(key);
    final account = find.byKey(const Key('workspaceAccount'));
    final trigger = utility && account.evaluate().isNotEmpty
        ? account
        : find.byKey(const Key('workspaceMore'));
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(action.last);
  await tester.pumpAndSettle();
}
