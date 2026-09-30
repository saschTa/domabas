import 'dart:ui' show SemanticsAction;

import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/document/views/document_processing_screen.dart';
import 'package:domabas/presentation/document/widgets/document_scheduling_summary.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_processing_repository.dart';

const _scheduling = DocumentProcessingScheduling(
  ingestionConcurrency: 5,
  aiConcurrency: 2,
  ollamaQueueSize: 11,
  ingestionConcurrencyMode: 'ollama_half_queue',
  aiConcurrencyMode: 'fixed',
  providerStepRetries: 4,
  priorityPolicy: 'ingestion_first',
);

void main() {
  for (final (width, scale, dark) in [
    (1100.0, 1.0, false),
    (320.0, 2.0, true),
  ]) {
    testWidgets(
      'scheduling explains shared resources and retries at $width/$scale',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: DocumentSchedulingSummary(scheduling: _scheduling),
              ),
            ),
          ),
        );
        expect(find.text('Shared resource limits'), findsOneWidget);
        expect(find.textContaining('Parallel jobs:'), findsNothing);
        expect(find.text('Ollama queue: 11 requests'), findsNothing);
        final details = find.text('Resource requirements');
        final detailSemantics = tester.getSemantics(details);
        expect(detailSemantics.label, 'Resource requirements');
        expect(
          detailSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(find.text('Ollama queue: 11 requests'), findsNothing);
        expect(
          find.textContaining('up to 4 times after the first request'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Paperless imports, email retrievals and thumbnail generation',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets('legacy scheduling does not invent installed capacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: DocumentSchedulingSummary()),
      ),
    );
    expect(find.text('Shared resource limits'), findsOneWidget);
    expect(find.textContaining('High priority'), findsNothing);
    expect(find.byKey(const Key('processingConcurrencySummary')), findsNothing);
    expect(find.text('Resource requirements'), findsOneWidget);
  });

  testWidgets('job list and details show outcomes without obsolete priority', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = FakeProcessingRepository()
      ..pipeline = testPipeline(scheduling: _scheduling)
      ..jobs = [
        testProcessingJob(id: 'ai', pipeline: 'ai', status: 'queued'),
        testProcessingJob(id: 'ingestion', status: 'succeeded'),
      ];
    final cubit = DocumentProcessingCubit(
      repository,
      canReadJobs: true,
      canReindex: false,
    );
    cubit.setActive(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DocumentProcessingScreen(
            cubit: cubit,
            canReadDocuments: true,
            onOpenDocument: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ai = find.byKey(const Key('job-ai'));
    await tester.ensureVisible(ai);
    expect(
      find.descendant(of: ai, matching: find.text('Background')),
      findsNothing,
    );
    expect(
      find.descendant(of: ai, matching: find.text('Queued')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('job-ingestion')),
        matching: find.text('High priority'),
      ),
      findsNothing,
    );
    await tester.tap(find.descendant(of: ai, matching: find.text('Details')));
    await tester.pumpAndSettle();
    expect(find.text('Background'), findsNothing);
    expect(find.text('Job details'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });
}
