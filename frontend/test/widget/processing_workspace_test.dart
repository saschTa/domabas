import '../support/fake_realtime_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_activity_repository.dart';

import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/document/views/document_processing_screen.dart';
import 'package:domabas/presentation/document/widgets/processing_widgets.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
  testWidgets(
    'job readers can still view reindex history without reindex permission',
    (tester) async {
      final repository = FakeProcessingRepository()
        ..namespaceBatches = [testReindexBatch(id: 'readonly-batch')];
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: false,
      )..setActive(true);
      await tester.pumpWidget(
        MaterialApp(
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
      await tester.scrollUntilVisible(
        find.byKey(const Key('showReindexRequests')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('processingPage')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const Key('showReindexRequests')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batch-readonly-batch')), findsOneWidget);
      expect(find.byKey(const Key('reindexLibrary')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );
  testWidgets(
    'pipeline and configuration expansion have independent storage identities',
    (tester) async {
      final cubit = DocumentProcessingCubit(
        FakeProcessingRepository(),
        canReadJobs: true,
        canReindex: true,
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
      await tester.scrollUntilVisible(
        find.byKey(const PageStorageKey('namespacePipeline')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('processingPage')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const PageStorageKey('namespacePipeline')));
      await tester.pumpAndSettle();
      expect(find.text('Configuration fingerprint'), findsNothing);
      await tester.ensureVisible(find.text('Configuration 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configuration 1'));
      await tester.pumpAndSettle();
      expect(find.text('Configuration fingerprint'), findsOneWidget);
      expect(find.text('b' * 64), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cubit.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'retained successful jobs do not invent individual stage completion',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PipelineDiagram(
                configuration: testPipelineConfiguration(),
                job: testProcessingJob(status: 'succeeded', reason: 'legacy'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Complete'), findsNothing);
      expect(find.text('Not recorded'), findsNWidgets(6));
    },
  );

  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets(
    'opening an older job starts at its outcome and returning preserves history position',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final repository = FakeProcessingRepository()
        ..jobs = List.generate(
          10,
          (index) => testProcessingJob(id: 'row-$index', status: 'succeeded'),
        );
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
      final history = find
          .descendant(
            of: find.byKey(const PageStorageKey('processingPage')),
            matching: find.byType(Scrollable),
          )
          .first;
      final row = find.byKey(const Key('job-row-9'));
      await tester.scrollUntilVisible(
        row,
        120,
        scrollable: history,
        maxScrolls: 50,
      );
      await Scrollable.ensureVisible(tester.element(row), alignment: .5);
      await tester.pumpAndSettle();
      final previous = tester.state<ScrollableState>(history).position.pixels;
      expect(previous, greaterThan(0));
      await tester.tap(
        find.descendant(of: row, matching: find.text('Details')),
      );
      await tester.pumpAndSettle();
      final detail = find
          .descendant(
            of: find.byKey(const PageStorageKey('processingJob-row-9')),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(tester.state<ScrollableState>(detail).position.pixels, 0);
      expect(find.text('Succeeded').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Back to jobs'));
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(history).position.pixels, previous);
      await cubit.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> mount(
    WidgetTester tester,
    FakeProcessingRepository repository,
    Iterable<String> claims, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AccountWorkspace(
          session: testSession(
            role: AccountRole.viewer,
            extraPermissions: claims,
          ),
          dependencies: AuthenticatedDependencies(
            realtime: FakeRealtimeRepository(),
            email: FakeEmailRepository(),
            activity: FakeActivityRepository(),
            documents: FakeDocumentRepository(),
            identity: FakeIdentityRepository(),
            processing: repository,
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
  }

  testWidgets(
    'processing-only system grant exposes its Admin destination independently',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final repository = FakeProcessingRepository();
      await mount(tester, repository, [
        IdentityPermission.manageDocumentProcessing,
      ]);
      expect(find.byKey(const Key('processingNavigation')), findsNothing);
      expect(
        find.byKey(const Key('navigation-admin-settings')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('navigation-admin-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manageSystemUsers')), findsNothing);
      await tester.tap(find.byKey(const Key('manageDocumentProcessing')));
      await tester.pumpAndSettle();
      expect(find.text('Document processing'), findsOneWidget);
      expect(repository.systemReads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'job read grant shows outcomes but cannot request reindex or open Admin',
    (tester) async {
      viewport(tester, const Size(1280, 900));
      final repository = FakeProcessingRepository()
        ..jobs = [testProcessingJob(status: 'failed')];
      await mount(tester, repository, [IdentityPermission.readDocumentJobs]);
      await tester.tap(find.byKey(const Key('processingNavigation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reindexLibrary')), findsNothing);
      expect(find.byKey(const Key('navigation-admin-settings')), findsNothing);
      expect(find.text('Shared resource limits'), findsOneWidget);
      await revealWorkspaceContent(
        tester,
        find.text('Details'),
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('processingPage')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Failed'), findsNWidgets(2));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Job details'), findsOneWidget);
      expect(find.text('Pipeline for this attempt'), findsOneWidget);
      expect(repository.namespaceRequests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'mobile reindex confirmation is explicit and preserves direct Documents navigation',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final repository = FakeProcessingRepository();
      await mount(tester, repository, [IdentityPermission.reindexDocuments]);
      expect(find.byKey(const Key('documentsNavigation')), findsOneWidget);
      await tester.tap(find.byKey(const Key('processingNavigation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('job-filter-all')), findsNothing);
      await tester.tap(find.byKey(const Key('reindexLibrary')));
      await tester.pumpAndSettle();
      expect(repository.namespaceRequests, isEmpty);
      expect(
        find.textContaining(
          'saved OCR corrections and original files are preserved',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirmReindex')));
      await tester.pumpAndSettle();
      expect(repository.namespaceRequests, hasLength(1));
      await tester.scrollUntilVisible(
        find.text('1 waiting'),
        80,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('1 waiting'), findsOneWidget);
      await tester.tap(find.byKey(const Key('documentsNavigation')));
      await tester.pumpAndSettle();
      final reads = repository.pipelineReads;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.pipelineReads, reads);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'realtime hint updates selected page-two job without discarding history',
    (tester) async {
      final repository = FakeProcessingRepository();
      var completed = false;
      repository.onJobs = (cursor, _) async => DocumentProcessingJobPage(
        items: [testProcessingJob(id: cursor ?? 'first')],
        nextCursor: cursor == null ? 'second' : null,
      );
      repository.onJob = (id) async => testProcessingJob(
        id: id,
        status: completed ? 'succeeded' : 'running',
      );
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
              canReadDocuments: false,
              onOpenDocument: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await cubit.load(moreJobs: true);
      await cubit.selectJob('second');
      await tester.pumpAndSettle();
      completed = true;
      cubit.invalidate();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(cubit.state.jobs.map((job) => job.id), ['first', 'second']);
      expect(cubit.state.selected!.status, 'succeeded');
      expect(find.text('Succeeded'), findsOneWidget);
      await cubit.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(1280, 900),
    const Size(390, 844),
    const Size(320, 320),
  ]) {
    testWidgets(
      'pipeline and settings remain usable at $size and 200 percent text',
      (tester) async {
        viewport(tester, size);
        final repository = FakeProcessingRepository();
        await mount(tester, repository, [
          IdentityPermission.manageDocumentProcessing,
        ], scale: 2);
        await navigateWorkspace(
          tester,
          'manageDocumentProcessing',
          group: 'Admin settings',
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(PipelineDiagram), findsOneWidget);
        final scroll = find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first;
        await revealWorkspaceContent(
          tester,
          find.byKey(const Key('saveProcessingSettings')),
          scrollable: scroll,
        );
        expect(tester.takeException(), isNull);
        await revealWorkspaceContent(
          tester,
          find.byKey(const Key('reindexSystem')),
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reindexSystem')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('confirmReindex')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
