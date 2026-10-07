import 'package:domabas/domain/paperless/models/paperless.dart';
import 'package:domabas/presentation/paperless/widgets/paperless_outcomes.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mock_paperless_repository.dart';

void main() {
  testWidgets('failed results are reachable beyond the first page on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var run = paperlessRun(
      outcomes: List.generate(
        25,
        (i) => PaperlessOutcome(
          sourceId: 25 - i,
          title: i == 24 ? 'Broken original' : 'Accepted file',
          status: i == 24 ? 'failed' : 'imported',
          failureCode: i == 24 ? 'download_failed' : null,
        ),
      ),
    );
    final repository = MockPaperlessRepository()..jobs = [run];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppPage(
              title: 'Import details',
              onRefresh: () async {
                setState(() => run = paperlessRun(outcomes: run.outcomes));
              },
              child: ListView(
                key: const Key('outcomePage'),
                children: [PaperlessOutcomes(repository: repository, run: run)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Broken original'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Failed'));
    await tester.pumpAndSettle();
    expect(repository.outcomeRequests.last, (null, 'failed'));
    expect(find.text('#1 · Broken original'), findsOneWidget);
    expect(find.textContaining('Error code: download_failed'), findsOneWidget);
    expect(find.textContaining('Accepted file'), findsNothing);
    final requests = repository.outcomeRequests.length;
    await tester.drag(
      find.byKey(const Key('outcomePage')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    expect(repository.outcomeRequests.length, requests + 1);
    expect(find.byTooltip('Refresh document results'), findsNothing);
    expect(repository.outcomeRequests.last, (null, 'failed'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Duplicates'));
    await tester.pumpAndSettle();
    expect(find.text('No duplicate documents.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'All results'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Accepted file'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
