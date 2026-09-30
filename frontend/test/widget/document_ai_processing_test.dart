import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_cubit.dart';
import 'package:domabas/presentation/document/widgets/document_properties_panel.dart';
import 'package:domabas/presentation/document/widgets/processing_widgets.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/document_ai_fixture.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_processing_repository.dart';

void main() {
  testWidgets('uncertain invoice decision stays visible after AI completes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 3500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final document = documentWithAI(
      status: 'succeeded',
      stage: 'complete',
      classification: const DocumentInvoiceClassification(
        decision: 'uncertain',
        reason: 'ambiguous',
        pass: 1,
        inputCharacters: 100,
        sourceCharacters: 100,
      ),
    );
    final repository = FakeDocumentRepository()..records = [document];
    final cubit = DocumentCubit(
      repository,
      id: document.id,
      capabilities: const DocumentCapabilities(read: true, retry: true),
      onUpdated: (_) {},
      onDeleted: (_) async {},
    );
    await cubit.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentPropertiesPanel(cubit: cubit, onCancel: () {}),
        ),
      ),
    );
    expect(
      find.text('Needs review · invoice decision uncertain'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('retryDocumentAI')), findsOneWidget);
    expect(find.text('Searchable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets('ready ingestion and failed AI have separate status and retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 3500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final document = documentWithAI();
    final repository = FakeDocumentRepository()..records = [document];
    final cubit = DocumentCubit(
      repository,
      id: document.id,
      capabilities: const DocumentCapabilities(read: true, retry: true),
      onUpdated: (_) {},
      onDeleted: (_) async {},
    );
    await cubit.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentPropertiesPanel(cubit: cubit, onCancel: () {}),
        ),
      ),
    );
    expect(find.text('Searchable'), findsOneWidget);
    expect(
      find.text('Failed / Checking and extracting invoice'),
      findsOneWidget,
    );
    expect(find.text('The model service was unavailable.'), findsOneWidget);
    expect(find.text('Retry processing'), findsNothing);
    final retry = find.byKey(const Key('retryDocumentAI'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repository.aiRetries, hasLength(1));
    expect(find.text('Searchable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
    'separate diagrams keep AI failure outside completed ingestion at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final config = testPipelineConfiguration(
        propertyExtractionEnabled: false,
        invoiceExtractionEnabled: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  PipelineDiagram(
                    configuration: config,
                    job: testProcessingJob(status: 'succeeded'),
                  ),
                  DocumentAIPipelineDiagram(
                    configuration: config,
                    job: testProcessingJob(
                      pipeline: 'ai',
                      status: 'failed',
                      stage: 'invoicing',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final diagrams = tester
          .widgetList<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
          .toList();
      expect(diagrams[0].steps.map((step) => step.title), [
        'Original',
        'OCR / extraction',
        'Embeddings',
        'Searchable',
      ]);
      expect(
        diagrams[0].steps.every(
          (step) => step.status == 'Complete' && !step.failed,
        ),
        isTrue,
      );
      expect(diagrams[1].steps.first.failed, isTrue);
      expect(diagrams[1].steps.last.status, 'Off for this attempt');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('structured invoices remain automatic with AI switches off', (
    tester,
  ) async {
    final config = testPipelineConfiguration(
      propertyExtractionEnabled: false,
      invoiceExtractionEnabled: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocumentAIPipelineDiagram(
              configuration: config,
              job: testProcessingJob(pipeline: 'ai', status: 'succeeded'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Structured invoice extraction'), findsOneWidget);
    expect(find.textContaining('without AI'), findsOneWidget);
    final steps = tester
        .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
        .steps;
    expect(steps.first.status, 'Complete');
    expect(steps.last.status, 'Off for this attempt');
  });
}
