import 'package:domabas/app/job_activity_cubit.dart';
import 'package:domabas/app/job_activity_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> exercisePaperlessSettings(
  WidgetTester tester,
  Future<void> Function(String) navigate,
) async {
  await navigate('managePaperless');
  final field = find.byType(DropdownButtonFormField<int>);
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (field.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(field, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(field), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text('3').last);
  await tester.pumpAndSettle();
  final save = find.byKey(const Key('savePaperlessSettings'));
  await Scrollable.ensureVisible(tester.element(save), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
  final saved = find.text('Paperless retrieval settings saved.');
  final savedDeadline = DateTime.now().add(const Duration(seconds: 15));
  while (saved.evaluate().isEmpty && DateTime.now().isBefore(savedDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(saved, findsOneWidget);
  await navigate('documentsNavigation');
  await navigate('managePaperless');
  final refreshedDeadline = DateTime.now().add(const Duration(seconds: 15));
  final persisted = find.text('Currently saved: 3 parallel retrievals.');
  while (persisted.evaluate().isEmpty &&
      DateTime.now().isBefore(refreshedDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(persisted, findsOneWidget);
  await navigate('documentsNavigation');
}

Future<void> exercisePaperlessWorkflow(
  WidgetTester tester,
  Future<void> Function(String) navigate,
) async {
  const token = String.fromEnvironment('PAPERLESS_FIXTURE_TOKEN');
  const server = String.fromEnvironment('PAPERLESS_FIXTURE_URL');
  expect(
    server,
    isNotEmpty,
    reason: 'The Paperless source URL must be supplied for UI entry.',
  );
  expect(
    token,
    isNotEmpty,
    reason: 'The Paperless API fixture must be configured for E2E.',
  );
  await navigate('paperlessNavigation');
  final serverField = find.byKey(const Key('paperlessServer'));
  final optionsDeadline = DateTime.now().add(const Duration(seconds: 15));
  while (serverField.evaluate().isEmpty &&
      DateTime.now().isBefore(optionsDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(serverField, findsOneWidget, reason: 'Paperless options have loaded');
  await tester.ensureVisible(serverField);
  await tester.pumpAndSettle();
  await tester.enterText(serverField, server);
  await tester.enterText(find.byKey(const Key('paperlessToken')), token);
  await Scrollable.ensureVisible(
    tester.element(find.byKey(const Key('paperlessStart'))),
    alignment: .5,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('paperlessStart')));
  await tester.pumpAndSettle();
  final acceptedDeadline = DateTime.now().add(const Duration(seconds: 15));
  while (tester
          .widget<TextField>(find.byKey(const Key('paperlessToken')))
          .controller!
          .text
          .isNotEmpty &&
      DateTime.now().isBefore(acceptedDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('paperlessToken')))
        .controller!
        .text,
    isEmpty,
  );
  await navigate('manageLibraries');
  await navigate('paperlessNavigation');
  Future<void> waitFor(String text) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(seconds: 1));
      final scroll = find
          .descendant(
            of: find.byKey(const Key('paperlessScroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scroll, const Offset(0, -350));
      await tester.pumpAndSettle();
      if (find.textContaining(text).evaluate().isNotEmpty) return;
    }
    fail('Paperless job did not reach $text');
  }

  await waitFor('Finished with document failures');
  final activity = tester
      .widget<JobActivityIndicator>(find.byType(JobActivityIndicator))
      .cubit;
  final activityDeadline = DateTime.now().add(const Duration(seconds: 15));
  while ((activity.state.discovering ||
          activity.state.stale ||
          activity.state.items.any(
            (item) => item.kind == JobActivityKind.paperless,
          )) &&
      DateTime.now().isBefore(activityDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(activity.state.discovering, isFalse);
  expect(activity.state.stale, isFalse);
  expect(activity.state.runningCount, isNotNull);
  expect(activity.state.queuedCount, isNotNull);
  expect(activity.state.batchCount, isNotNull);
  expect(
    activity.state.items.where(
      (item) => item.kind == JobActivityKind.paperless,
    ),
    isEmpty,
  );
  expect(
    find.text('2 discovered · 1 imported · 0 duplicates · 1 failed'),
    findsOneWidget,
  );
  await tester.ensureVisible(find.text('Show document results'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Show document results'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Paperless browser invoice'), findsOneWidget);
  expect(
    find.textContaining('Only PDF, PNG, JPEG and EML originals are supported.'),
    findsOneWidget,
  );
  final failedOutcomes = find.widgetWithText(ChoiceChip, 'Failed');
  await tester.ensureVisible(failedOutcomes);
  await tester.pumpAndSettle();
  await tester.tap(failedOutcomes);
  final filteredDeadline = DateTime.now().add(const Duration(seconds: 15));
  while ((find
              .textContaining('Paperless browser invoice')
              .evaluate()
              .isNotEmpty ||
          find
              .textContaining('Unsupported browser original')
              .evaluate()
              .isEmpty) &&
      DateTime.now().isBefore(filteredDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.widget<ChoiceChip>(failedOutcomes).selected, isTrue);
  expect(find.textContaining('Paperless browser invoice'), findsNothing);
  expect(find.textContaining('Unsupported browser original'), findsOneWidget);
  expect(find.textContaining('Error code:'), findsOneWidget);
  await navigate('processingNavigation');
  if (find.text('Back to jobs').evaluate().isNotEmpty) {
    await tester.tap(find.text('Back to jobs'));
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(
    find.text('Paperless import pipeline'),
    -300,
    scrollable: find.byType(Scrollable).last,
  );
  expect(find.text('Paperless import pipeline'), findsOneWidget);
  final filter = find.byKey(const Key('pipeline-filter-paperless'));
  await tester.scrollUntilVisible(
    filter,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await Scrollable.ensureVisible(tester.element(filter), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(filter);
  await tester.pumpAndSettle();
  final jobsDeadline = DateTime.now().add(const Duration(seconds: 30));
  Finder importRows() => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('paperless-job-'),
  );
  while (importRows().evaluate().isEmpty &&
      DateTime.now().isBefore(jobsDeadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(importRows(), findsOneWidget);
  final details = find.descendant(
    of: importRows(),
    matching: find.text('Details'),
  );
  await Scrollable.ensureVisible(tester.element(details), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(details);
  await tester.pumpAndSettle();
  expect(find.text('Job details'), findsOneWidget);
  expect(find.text('Partially completed'), findsOneWidget);
  expect(
    find.text('2 discovered · 1 imported · 0 duplicates · 1 failed'),
    findsOneWidget,
  );
  await tester.scrollUntilVisible(
    find.text('Document results'),
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  expect(
    find.textContaining('Only PDF, PNG, JPEG and EML originals are supported.'),
    findsOneWidget,
  );
  await tester.tap(find.text('Back to jobs'));
  await tester.pumpAndSettle();
  expect(tester.widget<ChoiceChip>(filter).selected, isTrue);
  await navigate('manageLibraries');
}
