import 'package:domabas/app/job_activity_cubit.dart';
import 'package:domabas/app/job_activity_indicator.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_email_repository.dart';
import '../support/fake_processing_repository.dart';

void main() {
  for (final known in [true, false]) {
    testWidgets(
      'Glacier real activity keeps ${known ? 'exact' : 'unknown'} totals separate from loaded rows',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var failed = false;
        final repository = FakeProcessingRepository()
          ..onJobs = (_, _) async {
            if (failed) {
              throw const DocumentProcessingFailure(
                DocumentProcessingFailureKind.unavailable,
              );
            }
            return DocumentProcessingJobPage(
              items: [testProcessingJob()],
              nextCursor: 'more',
              counts: known
                  ? {('ingestion', 'running'): 37, ('ingestion', 'queued'): 12}
                  : null,
            );
          };
        final jobs = JobActivityCubit(
          processing: repository,
          email: FakeEmailRepository(),
          canReadJobs: true,
          canReadBatches: false,
          canReadSystemBatches: false,
          canReadEmail: false,
          canReadPaperless: false,
        )..setActive(true);
        final opened = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: glacierMobileTheme(GlacierTheme.light()),
            home: AppWorkspaceShell(
              glacier: true,
              libraryLabel: 'Real library',
              libraryPicker: const SizedBox.shrink(),
              accountLabel: 'reader@example.test',
              onLogout: () {},
              groups: [
                AppNavigationGroup(
                  id: 'documents',
                  label: 'Documents',
                  icon: Icons.description,
                  items: const [
                    AppNavigationItem(
                      id: 'documents',
                      label: 'Documents',
                      icon: Icons.description,
                    ),
                  ],
                ),
              ],
              selectedId: 'documents',
              onSelected: (_) {},
              activityIndicator: JobActivityIndicator(
                glacier: true,
                cubit: jobs,
                uploads: null,
                onOpen: (item) => opened.add(item.id),
              ),
              child: const Center(child: Text('Real documents')),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final dock = tester.widget<GlacierActivityDock>(
          find.byType(GlacierActivityDock),
        );
        expect(dock.jobs.length, 1);
        expect(dock.summary!.count, known ? 49 : isNull);
        expect(dock.summary!.title, known ? '49 active jobs' : 'Activity');
        expect(
          dock.summary!.detail,
          contains(known ? '37 running' : 'Activity totals unavailable'),
        );
        final before = tester.getRect(find.text('Real documents'));
        expect(
          tester
              .getBottomRight(find.byKey(const Key('jobActivityIndicator')))
              .dy,
          lessThanOrEqualTo(
            tester
                .getTopLeft(find.byKey(const Key('workspaceBottomNavigation')))
                .dy,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('activity-dock-token')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          find
              .textContaining(
                known
                    ? '37 running · 12 queued'
                    : 'Activity totals unavailable',
              )
              .last,
          findsOneWidget,
        );
        expect(find.text('Invoice'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getRect(find.text('Real documents')), before);
        failed = true;
        await jobs.refresh();
        await tester.pump();
        final stale = tester.widget<GlacierActivityDock>(
          find.byType(GlacierActivityDock),
        );
        expect(stale.summary!.count, known ? 49 : isNull);
        expect(stale.stale, isTrue);
        expect(stale.summary!.running, isFalse);
        expect(stale.summary!.detail, contains('Job updates paused'));
        expect(opened, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await jobs.close();
      },
    );
  }
}
