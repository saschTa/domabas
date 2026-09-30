import 'dart:async';

import 'package:domabas/app/job_activity_cubit.dart';
import 'package:domabas/app/job_activity_indicator.dart';
import 'package:domabas/domain/document/interfaces/document_upload_repository.dart';
import 'package:domabas/domain/document/interfaces/document_upload_scheduler.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_upload.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_uploads_cubit.dart';
import 'package:domabas/presentation/document/widgets/processing_widgets.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_email_repository.dart';
import '../support/fake_processing_repository.dart';

DocumentReindexBatch progressBatch({
  bool enumerated = true,
  String status = 'running',
}) => DocumentReindexBatch(
  id: 'batch',
  scope: 'namespace',
  reason: 'manual',
  status: status,
  configurationRevision: 1,
  configurationFingerprint: 'b' * 64,
  createdAt: DateTime.utc(2026),
  enumerationComplete: enumerated,
  discovered: 10,
  waiting: 3,
  running: 1,
  succeeded: 2,
  failed: 1,
  skipped: 2,
  superseded: 1,
);

final class _WaitingScheduler implements DocumentUploadScheduler {
  _WaitingScheduler({this.waiting = true});
  final bool waiting;
  bool occupied = false;
  @override
  bool get contentBusy => waiting || occupied;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  bool start(Future<void> Function() operation) {
    if (contentBusy) return false;
    occupied = true;
    unawaited(operation());
    return true;
  }
}

final class _NoUpload implements DocumentUploadRepository {
  _NoUpload({this.hold = false});
  final bool hold;
  @override
  Future<DocumentUploadResult> upload(
    DocumentUploadCandidate candidate, {
    required Future<void> cancel,
    required void Function() onSending,
    void Function(Document)? onAccepted,
    void Function(String)? onReadFailure,
  }) async {
    if (!hold) throw StateError('Uploads should stay queued');
    onSending();
    await cancel;
    return const DocumentUploadResult(
      outcome: DocumentUploadOutcome.rejected,
      message: 'Cancelled',
    );
  }

  @override
  void release(Iterable<String> ids) {}
  @override
  void dispose() {}
}

void main() {
  testWidgets(
    'active upload stays visible with stale jobs and long filenames, ahead of queued files',
    (tester) async {
      final repository = FakeProcessingRepository()
        ..jobs = [testProcessingJob()];
      final jobs = JobActivityCubit(
        processing: repository,
        email: FakeEmailRepository(),
        canReadJobs: true,
        canReadBatches: false,
        canReadSystemBatches: false,
        canReadEmail: false,
        canReadPaperless: false,
      )..setActive(true);
      final uploads = DocumentUploadsCubit(
        repository: _NoUpload(hold: true),
        scheduler: _WaitingScheduler(waiting: false),
        libraryName: 'Personal library',
        canRead: true,
        allowed: true,
      );
      final filename = '${'Long file name ' * 16}.pdf';
      uploads.reserveBatch(20);
      uploads.receiveBatch(
        List.generate(
          20,
          (index) => DocumentUploadCandidate(
            id: '$index',
            displayName: index == 0 ? filename : 'Waiting $index.pdf',
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: JobActivityIndicator(
              cubit: jobs,
              uploads: uploads,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      repository.onJobs = (_, _) async => throw const DocumentProcessingFailure(
        DocumentProcessingFailureKind.unavailable,
      );
      await jobs.refresh();
      await tester.pump();
      final card = tester.widget<AppJobActivityCard>(
        find.byType(AppJobActivityCard),
      );
      expect(card.running, isTrue);
      expect(card.subtitle, contains('Job updates paused'));
      expect(
        tester.getSize(find.byKey(const Key('jobActivityIndicator'))).height,
        lessThan(160),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const Key('jobActivityIndicator')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widgetList<AppRecordRow>(find.byType(AppRecordRow)).first.title,
        filename,
      );
      expect(find.text('Uploading'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await jobs.close();
      await tester.runAsync(uploads.close);
    },
  );
  for (final (size, scale, dark) in [
    (const Size(1280, 900), 1.0, false),
    (const Size(390, 844), 1.0, true),
    (const Size(320, 800), 2.0, false),
    (const Size(320, 320), 2.0, true),
  ]) {
    testWidgets('shared upload/job activity fits $size at $scale dark=$dark', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final repository = FakeProcessingRepository()
        ..jobs = [testProcessingJob()]
        ..namespaceBatches = [progressBatch()];
      final jobs = JobActivityCubit(
        processing: repository,
        email: FakeEmailRepository(),
        canReadJobs: true,
        canReadBatches: true,
        canReadSystemBatches: false,
        canReadEmail: false,
        canReadPaperless: false,
      )..setActive(true);
      final uploads = DocumentUploadsCubit(
        repository: _NoUpload(),
        scheduler: _WaitingScheduler(),
        libraryName: 'Personal library',
        canRead: true,
        allowed: true,
      );
      uploads.reserveBatch(1);
      uploads.receiveBatch([
        const DocumentUploadCandidate(
          id: 'upload',
          displayName: 'Annual report.pdf',
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: AppWorkspaceShell(
            groups: [
              AppNavigationGroup(
                id: 'documents',
                label: 'Documents',
                icon: Icons.description,
                items: [
                  const AppNavigationItem(
                    id: 'documents',
                    label: 'Documents',
                    icon: Icons.description,
                  ),
                ],
              ),
            ],
            selectedId: 'documents',
            onSelected: (_) {},
            libraryPicker: const Text('Personal library'),
            accountLabel: 'reader@example.com',
            onLogout: () {},
            activityIndicator: JobActivityIndicator(
              cubit: jobs,
              uploads: uploads,
              onOpen: (_) {},
            ),
            child: const Center(child: Text('Documents remain available')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final indicator = find.byKey(const Key('jobActivityIndicator'));
      expect(indicator, findsOneWidget);
      final rect = tester.getRect(indicator);
      expect(rect.width, lessThanOrEqualTo(280));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      if (size.width < 600) {
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        final navigation = tester.getRect(
          find.byWidget(scaffold.bottomNavigationBar!),
        );
        expect(rect.bottom, lessThanOrEqualTo(navigation.top));
      }
      await tester.tap(indicator);
      await tester.pumpAndSettle();
      expect(find.text('Uploads'), findsOneWidget);
      expect(find.text('Annual report.pdf'), findsOneWidget);
      expect(
        find.text('Activity'),
        size.height < 420 || scale > 1.7 ? findsOneWidget : findsNWidgets(2),
      );
      expect(find.byKey(const Key('uploadFeedback')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Documents remain available'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await jobs.close();
      await tester.runAsync(uploads.close);
    });
  }

  testWidgets(
    'running spinners animate, discovery has no percentage and reduced motion stops activity',
    (tester) async {
      Widget content({required bool reduced, required bool enumerated}) =>
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: ReindexBatchCard(
                  batch: progressBatch(enumerated: enumerated),
                ),
              ),
            ),
          );
      await tester.pumpWidget(content(reduced: false, enumerated: false));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<AppStripedProgressIndicator>(
              find.byType(AppStripedProgressIndicator),
            )
            .value,
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(find.text('Finding originals · 10 found'), findsOneWidget);
      await tester.pumpWidget(content(reduced: true, enumerated: false));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester
            .widget<AppStripedProgressIndicator>(
              find.byType(AppStripedProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(content(reduced: true, enumerated: true));
      await tester.pumpAndSettle();
      expect(find.text('6 of 10 finished · 60%'), findsOneWidget);
      expect(
        tester
            .widget<AppStripedProgressIndicator>(
              find.byType(AppStripedProgressIndicator),
            )
            .value,
        .6,
      );
    },
  );
}
