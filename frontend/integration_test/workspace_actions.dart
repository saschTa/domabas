import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> refreshWorkspacePage(
  WidgetTester tester, {
  required Finder list,
}) async {
  final scroll = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scroll).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pumpAndSettle();
  final viewport = tester.getRect(list);
  await tester.dragFrom(
    Offset(viewport.center.dx, viewport.top + 32),
    Offset(0, (viewport.height * .75).clamp(240, 500)),
  );
  await tester.pumpAndSettle();
}

Future<void> revealWorkspacePageContent(
  WidgetTester tester,
  Finder target, {
  required Finder list,
  bool center = true,
}) async {
  if (target.evaluate().isEmpty) {
    await tester.drag(list, const Offset(0, 10000));
    await tester.pumpAndSettle();
  }
  Rect? previousTarget;
  Rect? previousViewport;
  for (var attempt = 0; attempt < 80; attempt++) {
    var viewport = tester.getRect(list);
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
    final bounds = target.evaluate().isEmpty ? null : tester.getRect(target);
    final delta = bounds == null
        ? -250.0
        : viewport.center.dy - bounds.center.dy;
    final settled =
        bounds != null &&
        bounds == previousTarget &&
        viewport == previousViewport;
    final clearOfFeedback =
        bounds != null &&
        bounds.left >= viewport.left &&
        bounds.right <= viewport.right &&
        bounds.top >= viewport.top &&
        bounds.bottom <= viewport.bottom - 80;
    if (target.hitTestable().evaluate().isNotEmpty &&
        (!center || delta.abs() <= 24 || (settled && clearOfFeedback))) {
      return;
    }
    previousTarget = bounds;
    previousViewport = viewport;
    await tester.dragFrom(
      viewport.center,
      Offset(0, delta.clamp(-250.0, 250.0)),
    );
    await tester.pumpAndSettle();
  }
  fail('Could not reveal $target in the workspace page viewport.');
}

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
    final mobileMore = find.byKey(const Key('navigation-more'));
    final trigger = mobileMore.evaluate().isNotEmpty
        ? mobileMore
        : utility && account.evaluate().isNotEmpty
        ? account
        : find.byKey(const Key('workspaceMore'));
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(action.last);
  await tester.pumpAndSettle();
}

Future<void> revealWorkspaceHeader(WidgetTester tester, Finder target) async {
  final toolbarTarget = find.descendant(
    of: find.byKey(const Key('workspaceHeader')),
    matching: target,
  );
  if (toolbarTarget.evaluate().isNotEmpty) {
    await tester.ensureVisible(toolbarTarget);
    await tester.pumpAndSettle();
    expect(toolbarTarget.hitTestable(), findsOneWidget);
    return;
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> openWorkspaceJobFilters(WidgetTester tester) async {
  if (find.text('Filter jobs').evaluate().isNotEmpty) return;
  final trigger = find.byKey(const Key('jobFilters'));
  await revealWorkspaceHeader(tester, trigger);
  await tester.tap(trigger);
  await tester.pumpAndSettle();
}

Future<void> closeWorkspaceJobFilters(WidgetTester tester) async {
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

Future<void> selectWorkspaceJobFilters(
  WidgetTester tester,
  Iterable<String> keys,
) async {
  await openWorkspaceJobFilters(tester);
  for (final key in keys) {
    final filter = find.byKey(Key(key));
    await tester.ensureVisible(filter);
    await tester.pumpAndSettle();
    await tester.tap(filter);
    await tester.pumpAndSettle();
  }
  await closeWorkspaceJobFilters(tester);
}

Future<void> setWorkspacePipelineSetup(
  WidgetTester tester, {
  required bool expanded,
}) async {
  final setup = find.byKey(const PageStorageKey('pipelineSetup'));
  final title = find.text('Pipeline setup');
  await revealWorkspacePageContent(
    tester,
    title,
    list: find.byKey(const PageStorageKey('processingPage')),
    center: false,
  );
  final open = find
      .descendant(of: setup, matching: find.text('Shared resource limits'))
      .evaluate()
      .isNotEmpty;
  if (open != expanded) {
    await tester.tap(title);
    await tester.pumpAndSettle();
  }
}
