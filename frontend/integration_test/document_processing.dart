import 'package:domabas_api/api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> exerciseDocumentProcessing(
  WidgetTester tester, {
  required api.DocumentsApi documents,
  required String correctedDocumentId,
  required String correction,
  required String imageId,
}) async {
  debugPrint('Document processing E2E: reindex original files through UI');
  final original = await documents.downloadDocumentWithHttpInfo(
    correctedDocumentId,
  );
  expect(original.statusCode, 200);
  final oldJobs = (await documents.listDocumentJobs(
    documentId: correctedDocumentId,
    pipeline: 'ingestion',
    limit: 50,
  ))!;
  final previousGeneration = oldJobs.items
      .map((job) => job.generation!)
      .reduce((a, b) => a > b ? a : b);
  final existingBatches = (await documents.listDocumentReindexBatches(
    limit: 50,
  ))!.items.map((batch) => batch.id).toSet();
  await tester.tap(find.byKey(const Key('processingNavigation')));
  await tester.pumpAndSettle();
  await _wait(
    tester,
    () => find
        .byKey(const Key('reindexLibrary'))
        .hitTestable()
        .evaluate()
        .any(
          (element) => (element.widget as ButtonStyleButton).onPressed != null,
        ),
    'reindex action loaded',
  );
  await tester.tap(find.byKey(const Key('reindexLibrary')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('confirmReindex')), findsOneWidget);
  await tester.tap(find.byKey(const Key('confirmReindex')));
  await tester.pumpAndSettle();

  api.DocumentReindexBatch? accepted;
  final acceptanceDeadline = DateTime.now().add(const Duration(seconds: 30));
  while (accepted == null && DateTime.now().isBefore(acceptanceDeadline)) {
    final page = (await documents.listDocumentReindexBatches(limit: 50))!;
    for (final batch in page.items) {
      if (!existingBatches.contains(batch.id)) accepted = batch;
    }
    if (accepted == null) await tester.pump(const Duration(milliseconds: 200));
  }
  expect(accepted, isNotNull, reason: 'UI request was durably accepted');
  final batchId = accepted!.id;
  await _wait(
    tester,
    () => find.byKey(const Key('jobActivityIndicator')).evaluate().isNotEmpty,
    'reindex activity appears outside the history',
  );
  await tester.tap(find.byKey(const Key('documentsNavigation')));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byKey(const Key('jobActivityIndicator')), findsOneWidget);
  await tester.tap(find.byKey(const Key('jobActivityIndicator')));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Reindex · Current library'), findsOneWidget);
  await tester.tap(find.text('Close'));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byKey(const Key('processingNavigation')));
  await tester.pump(const Duration(milliseconds: 400));
  await _reveal(tester, find.byKey(const Key('showReindexRequests')));
  await tester.tap(find.byKey(const Key('showReindexRequests')));
  await tester.pump(const Duration(milliseconds: 400));
  final processingDeadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(processingDeadline)) {
    accepted = (await documents.getDocumentReindexBatch(batchId))!;
    if (!['enumerating', 'running'].contains(accepted.status.toString())) break;
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(accepted!.status.toString(), 'succeeded');
  expect(accepted.enumerationComplete, isTrue);
  expect(accepted.succeeded, 2);
  expect(accepted.skipped, greaterThanOrEqualTo(1));
  expect(accepted.failed, 0);
  expect(
    (await documents.getDocumentOCR(correctedDocumentId))!.text,
    correction,
  );
  final afterOriginal = await documents.downloadDocumentWithHttpInfo(
    correctedDocumentId,
  );
  expect(afterOriginal.bodyBytes, original.bodyBytes);
  expect(
    (await documents.getDocumentProcessing(imageId))!.state.toString(),
    'ready',
  );
  final jobs = (await documents.listDocumentJobs(
    documentId: correctedDocumentId,
    pipeline: 'ingestion',
    limit: 50,
  ))!.items;
  expect(jobs.any((job) => job.reason.toString() == 'ocr_correction'), isTrue);
  final reindexed = jobs.singleWhere(
    (job) =>
        job.reason.toString() == 'reindex' &&
        job.generation! > previousGeneration,
  );
  expect(reindexed.status.toString(), 'succeeded');
  expect(reindexed.textSource.toString(), 'manual');
  expect(jobs.length, greaterThan(oldJobs.items.length));

  await tester.tap(find.byTooltip('Refresh processing'));
  await tester.pumpAndSettle();
  await _reveal(tester, find.byKey(Key('batch-$batchId')));
  expect(find.text('2 succeeded'), findsOneWidget);
  await _reveal(tester, find.widgetWithText(ChoiceChip, 'Jobs'));
  await tester.tap(find.widgetWithText(ChoiceChip, 'Jobs'));
  await tester.pumpAndSettle();
  final row = find.byKey(Key('job-${reindexed.id}'));
  final details = find.descendant(
    of: row,
    matching: find.widgetWithText(TextButton, 'Details'),
  );
  await _reveal(tester, details);
  await tester.tap(details);
  await _wait(
    tester,
    () => find.text('Job details').evaluate().isNotEmpty,
    'new job detail loaded',
  );
  expect(find.text('Succeeded'), findsOneWidget);
  await _reveal(tester, find.byKey(const Key('openJobDocument')));
  await tester.tap(find.byKey(const Key('openJobDocument')));
  await _wait(
    tester,
    () => find.byKey(const Key('closeDocument')).evaluate().isNotEmpty,
    'job opens its document',
  );
  await tester.tap(find.byKey(const Key('closeDocument')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('documentsNavigation')));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: reason);
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scroll = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scroll).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    80,
    scrollable: scroll,
    maxScrolls: 100,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}
