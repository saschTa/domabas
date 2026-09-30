import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/paperless/models/paperless.dart';
import 'package:domabas/presentation/email/widgets/email_pipeline_diagram.dart';
import 'package:domabas/presentation/document/widgets/processing_widgets.dart';
import 'package:domabas/presentation/paperless/widgets/paperless_pipeline.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';
import '../support/mock_paperless_repository.dart';
import '../support/workspace_navigation.dart';

EmailRun run(
  String id,
  int day, {
  String status = 'succeeded',
  String stage = 'complete',
  int attachmentsFailed = 0,
}) => EmailRun(
  id: id,
  providerId: 'provider',
  namespaceId: 'library',
  reason: 'scheduled',
  status: status,
  stage: stage,
  createdAt: DateTime.utc(2026, 9, day),
  startedAt: DateTime.utc(2026, 9, day),
  messagesAccepted: 1,
  attachmentsAccepted: 2,
  attachmentsFailed: attachmentsFailed,
);

final class PagedEmailRepository extends FakeEmailRepository {
  bool expanded = false;
  @override
  Future<EmailRunPage> listRuns(
    String? providerId, {
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) async {
    expect(providerId, isNull);
    if (cursor != null) expanded = true;
    return EmailRunPage(
      items: [runs[cursor == null ? 'new-mail' : 'old-mail']!],
      nextCursor: cursor == null ? 'next' : null,
    );
  }
}

void main() {
  testWidgets(
    'thumbnail filter uses full totals and retains selection after details',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final thumbnail = DocumentProcessingJob(
        id: 'thumbnail',
        documentId: '11111111-1111-4111-8111-111111111111',
        documentTitle: 'Preview source',
        pipeline: 'thumbnail',
        attempt: 1,
        rendererRevision: 1,
        reason: 'automatic',
        status: 'succeeded',
        stage: 'complete',
        createdAt: DateTime.utc(2026, 9, 24),
        updatedAt: DateTime.utc(2026, 9, 24),
        isCurrent: true,
        documentDeleted: false,
      );
      final processing = FakeProcessingRepository()
        ..jobs = [
          thumbnail,
          testProcessingJob(id: 'ingestion', status: 'succeeded'),
        ];
      processing.onPipelineJobs = (cursor, status, pipeline) async =>
          DocumentProcessingJobPage(
            items: processing.jobs.where(
              (job) =>
                  (pipeline == null || job.pipeline == pipeline) &&
                  (status == null || job.status == status),
            ),
            counts: {
              ('thumbnail', 'succeeded'): 7,
              ('ingestion', 'succeeded'): 4,
            },
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AccountWorkspace(
            session: testSession(
              extraPermissions: [IdentityPermission.readDocumentJobs],
            ),
            dependencies: AuthenticatedDependencies(
              paperless: MockPaperlessRepository(),
              realtime: FakeRealtimeRepository(),
              email: FakeEmailRepository(),
              activity: FakeActivityRepository(),
              documents: FakeDocumentRepository(),
              identity: FakeIdentityRepository(),
              processing: processing,
              externalLinks: FakeExternalLinkLauncher(),
              close: () {},
            ),
            onLogout: () {},
            onSessionEnded: (_) {},
            onSwitch: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await navigateWorkspace(tester, 'processingNavigation');
      await tester.pumpAndSettle();
      expect(find.text('Thumbnail generation pipeline'), findsOneWidget);
      final filter = find.byKey(const Key('pipeline-filter-thumbnail'));
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('job-thumbnail')), findsOneWidget);
      expect(find.byKey(const Key('job-ingestion')), findsOneWidget);
      expect(
        find.descendant(of: filter, matching: find.text('7')),
        findsOneWidget,
      );
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(processing.jobPipelines.last, 'thumbnail');
      expect(find.byKey(const Key('job-ingestion')), findsNothing);
      final details = find.descendant(
        of: find.byKey(const Key('job-thumbnail')),
        matching: find.text('Details'),
      );
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('Job details'), findsOneWidget);
      expect(find.byType(DocumentThumbnailPipelineDiagram), findsOneWidget);
      expect(find.byType(ProcessingConfigurationDetails), findsNothing);
      expect(find.text('Thumbnail renderer revision 1'), findsOneWidget);
      await tester.tap(find.text('Back to jobs'));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(filter).selected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final status in [
    'queued',
    'running',
    'succeeded',
    'failed',
    'superseded',
  ]) {
    testWidgets(
      'thumbnail diagram records $status at 320px and enlarged text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final job = testProcessingJob(
          pipeline: 'thumbnail',
          attempt: 1,
          status: status,
          stage: status == 'queued'
              ? 'queued'
              : status == 'succeeded'
              ? 'complete'
              : 'rendering',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DocumentThumbnailPipelineDiagram(job: job),
              ),
            ),
          ),
        );
        await tester.pump();
        final steps = tester
            .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
            .steps;
        expect(steps[1].current, status == 'running');
        expect(steps[1].failed, status == 'failed');
        expect(
          steps[2].status,
          status == 'succeeded'
              ? 'Complete'
              : status == 'superseded'
              ? 'Superseded'
              : status == 'failed'
              ? 'Not completed'
              : 'Waiting',
        );
        expect(
          tester
              .getTopLeft(find.byKey(const Key('thumbnail-pipeline-stage-1')))
              .dy,
          greaterThan(
            tester
                .getBottomLeft(
                  find.byKey(const Key('thumbnail-pipeline-stage-0')),
                )
                .dy,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('older failed thumbnail does not invent rendering evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentThumbnailPipelineDiagram(
            job: testProcessingJob(
              pipeline: 'thumbnail',
              attempt: 1,
              status: 'failed',
              stage: 'failed',
            ),
          ),
        ),
      ),
    );
    final steps = tester
        .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
        .steps;
    expect(
      steps.every(
        (step) =>
            step.status == 'Not recorded' && !step.failed && !step.current,
      ),
      isTrue,
    );
  });

  testWidgets(
    'one paginated chronological list filters pipelines and opens the same detail page',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final email = PagedEmailRepository()
        ..providers['provider'] = emailProvider()
        ..runs['new-mail'] = run('new-mail', 19)
        ..runs['old-mail'] = run('old-mail', 17);
      final processing = FakeProcessingRepository()
        ..jobs = [testProcessingJob(id: 'document', status: 'succeeded')];
      final paperless = MockPaperlessRepository()
        ..jobs = [
          paperlessRun(
            id: 'paperless',
            state: 'succeeded',
            discovered: 2,
            imported: 1,
            failed: 1,
            createdAt: DateTime.utc(2026, 9, 18, 12),
            outcomes: const [
              PaperlessOutcome(
                sourceId: 2,
                title: 'Unsupported file',
                status: 'failed',
                failureCode: 'unsupported_media_type',
              ),
            ],
          ),
        ];
      final dependencies = AuthenticatedDependencies(
        paperless: paperless,
        realtime: FakeRealtimeRepository(),
        email: email,
        activity: FakeActivityRepository(),
        documents: FakeDocumentRepository(),
        identity: FakeIdentityRepository(),
        processing: processing,
        externalLinks: FakeExternalLinkLauncher(),
        close: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AccountWorkspace(
            session: testSession(
              extraPermissions: [
                IdentityPermission.manageEmail,
                IdentityPermission.readDocumentJobs,
                IdentityPermission.importPaperless,
                IdentityPermission.uploadDocuments,
              ],
            ),
            dependencies: dependencies,
            onLogout: () {},
            onSessionEnded: (_) {},
            onSwitch: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await navigateWorkspace(tester, 'processingNavigation');
      await tester.pumpAndSettle();
      expect(find.text('Paperless import pipeline'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('pipeline-filter-document')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('processingPage')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('email-job-new-mail')), findsOneWidget);
      expect(
        find.byKey(const Key('paperless-job-paperless')),
        findsNothing,
        reason: 'Unread email history also bounds the Paperless records.',
      );
      expect(
        find.byKey(const Key('job-document')),
        findsNothing,
        reason: 'A newer unread email page may precede the document.',
      );
      await tester.ensureVisible(find.byKey(const Key('loadMorePipelineJobs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('loadMorePipelineJobs')));
      await tester.pumpAndSettle();
      expect(email.expanded, isTrue);
      final rows = tester
          .widgetList<AppRecordRow>(find.byType(AppRecordRow))
          .map((row) => row.key)
          .toList();
      expect(rows, [
        const Key('email-job-new-mail'),
        const Key('paperless-job-paperless'),
        const Key('job-document'),
        const Key('email-job-old-mail'),
      ]);
      await tester.ensureVisible(
        find.byKey(const Key('pipeline-filter-document')),
      );
      await tester.tap(find.byKey(const Key('pipeline-filter-document')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('job-document')), findsOneWidget);
      expect(find.byKey(const Key('email-job-new-mail')), findsNothing);
      expect(find.byKey(const Key('paperless-job-paperless')), findsNothing);
      await tester.tap(find.byKey(const Key('pipeline-filter-paperless')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('job-document')), findsNothing);
      expect(find.byKey(const Key('email-job-new-mail')), findsNothing);
      expect(find.byKey(const Key('paperless-job-paperless')), findsOneWidget);
      await tester.tap(find.byKey(const Key('job-filter-succeeded')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paperless-job-paperless')), findsNothing);
      await tester.tap(find.byKey(const Key('job-filter-partial')));
      await tester.pumpAndSettle();
      final paperlessDetail = find.descendant(
        of: find.byKey(const Key('paperless-job-paperless')),
        matching: find.text('Details'),
      );
      await tester.ensureVisible(paperlessDetail);
      await tester.tap(paperlessDetail);
      await tester.pumpAndSettle();
      expect(find.text('Job details'), findsOneWidget);
      expect(
        find.text('2 discovered · 1 imported · 0 duplicates · 1 failed'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('paperless-pipeline-stage-0')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppPipelineDiagram), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Document results'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.textContaining(
          'Only PDF, PNG, JPEG and EML originals are supported.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Back to jobs'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('pipeline-filter-paperless')),
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const Key('pipeline-filter-paperless')),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('job-filter-all')));
      await tester.tap(find.byKey(const Key('pipeline-filter-email')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('job-document')), findsNothing);
      final detail = find.descendant(
        of: find.byKey(const Key('email-job-new-mail')),
        matching: find.text('Details'),
      );
      await tester.ensureVisible(detail);
      await tester.tap(detail);
      await tester.pumpAndSettle();
      expect(find.text('Job details'), findsOneWidget);
      expect(find.text('Pipeline for this attempt'), findsOneWidget);
      expect(
        find.text('Emails: 1 accepted · 0 reused · 0 skipped · 0 failed'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('email-pipeline-stage-0')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppPipelineDiagram), findsOneWidget);
      await tester.tap(find.text('Back to jobs'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('pipeline-filter-email')))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
    },
  );

  for (final canImport in [false, true]) {
    testWidgets('Paperless jobs respect import permissions: $canImport', (
      tester,
    ) async {
      final paperless = MockPaperlessRepository()..jobs = [paperlessRun()];
      final dependencies = AuthenticatedDependencies(
        paperless: paperless,
        realtime: FakeRealtimeRepository(),
        email: FakeEmailRepository(),
        activity: FakeActivityRepository(),
        documents: FakeDocumentRepository(),
        identity: FakeIdentityRepository(),
        processing: FakeProcessingRepository(),
        externalLinks: FakeExternalLinkLauncher(),
        close: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AccountWorkspace(
            session: testSession(
              extraPermissions: [
                IdentityPermission.importPaperless,
                if (canImport)
                  IdentityPermission.uploadDocuments
                else
                  IdentityPermission.manageEmail,
              ],
            ),
            dependencies: dependencies,
            onLogout: () {},
            onSessionEnded: (_) {},
            onSwitch: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(paperless.lists, canImport ? greaterThan(0) : 0);
      await navigateWorkspace(tester, 'processingNavigation');
      expect(
        find.text('Paperless import pipeline'),
        canImport ? findsOneWidget : findsNothing,
      );
      if (canImport) {
        await revealWorkspaceContent(
          tester,
          find.byKey(const Key('pipeline-filter-paperless')),
          scrollable: find.descendant(
            of: find.byKey(const PageStorageKey('processingPage')),
            matching: find.byType(Scrollable),
          ),
        );
      }
      expect(
        find.byKey(const Key('pipeline-filter-paperless')),
        canImport ? findsOneWidget : findsNothing,
      );
      expect(paperless.lists, canImport ? greaterThan(0) : 0);
      if (canImport) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        final reads = paperless.lists;
        await tester.pump(const Duration(seconds: 30));
        expect(paperless.lists, reads);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(paperless.lists, greaterThan(reads));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
    });
  }

  for (final size in [const Size(320, 700), const Size(1400, 900)]) {
    testWidgets(
      'Paperless boxes show recorded progress and missing failure stage at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Future<void> show(PaperlessRun value) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PaperlessPipelineDiagram(run: value),
              ),
            ),
          ),
        );
        List<AppPipelineStep> steps() => tester
            .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
            .steps;
        await show(
          paperlessRun(state: 'running', stage: 'importing', imported: 1),
        );
        expect(steps()[1].status, 'Complete');
        expect(steps()[2].current, isTrue);
        expect(steps()[3].status, 'Queued as document jobs');
        await show(paperlessRun(state: 'succeeded', imported: 1, failed: 1));
        expect(steps()[2].failed, isTrue);
        expect(steps()[2].status, 'Completed with failures');
        await show(paperlessRun(state: 'failed'));
        expect(
          steps().take(3).every((s) => s.status == 'Not recorded'),
          isTrue,
        );
        await show(paperlessRun(state: 'cancelled'));
        expect(
          steps().take(3).every((s) => s.status == 'Not recorded'),
          isTrue,
        );
        await show(paperlessRun(state: 'succeeded', duplicates: 2));
        expect(steps()[3].status, 'No new files imported');
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('email boxes show stopped and partial steps at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> show(EmailRun value) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EmailPipelineDiagram(run: value),
            ),
          ),
        ),
      );
      await show(run('failed', 19, status: 'failed', stage: 'fetching'));
      expect(find.text('Stopped here'), findsOneWidget);
      final failed = tester
          .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
          .steps;
      expect(failed[3].failed, isTrue);
      expect(failed[4].status, 'Not completed');
      expect(failed[5].status, 'Queued as document jobs');
      await show(run('partial', 19, status: 'partial', attachmentsFailed: 1));
      final partial = tester
          .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
          .steps;
      expect(partial[3].status, 'Complete');
      expect(partial[4].status, 'Completed with failures');
      expect(partial[4].failed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
