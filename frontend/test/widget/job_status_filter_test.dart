import 'package:domabas/app/processing_jobs_list.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/email/cubits/email_jobs_cubit.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_jobs_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_email_repository.dart';
import '../support/fake_processing_repository.dart';

void main() {
  testWidgets('status chips search older jobs and reset each filtered page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final history = [
      for (final status in ['queued', 'failed', 'succeeded'])
        for (var i = 0; i < 25; i++)
          testProcessingJob(id: '$status-$i', status: status),
    ];
    final requests = <(String?, String?)>[];
    final repository = FakeProcessingRepository()
      ..onJobs = (cursor, status) async {
        requests.add((cursor, status));
        final items = history
            .where((job) => status == null || job.status == status)
            .toList();
        final offset = int.parse(cursor ?? '0');
        return DocumentProcessingJobPage(
          items: items.skip(offset).take(20),
          nextCursor: offset + 20 < items.length ? '${offset + 20}' : null,
        );
      };
    final documents = DocumentProcessingCubit(
      repository,
      canReadJobs: true,
      canReindex: false,
    )..setActive(true);
    final email = EmailJobsCubit(FakeEmailRepository(), allowed: false);
    final paperless = PaperlessJobsCubit(null, allowed: false);
    addTearDown(documents.close);
    addTearDown(email.close);
    addTearDown(paperless.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProcessingJobsList(
              documents: documents,
              email: email,
              paperless: paperless,
              onOpenEmailJob: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(documents.state.jobs.every((job) => job.status == 'queued'), isTrue);
    for (final status in ['failed', 'succeeded']) {
      final filter = find.byKey(Key('job-filter-$status'));
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(requests.last, (null, status));
      expect(documents.state.jobs.length, 20);
      expect(documents.state.jobs.every((job) => job.status == status), isTrue);
      expect(documents.state.browsingHistory, isFalse);
      expect(find.text('No jobs to show'), findsNothing);
      final more = find.byKey(const Key('loadMorePipelineJobs'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(requests.last, ('20', status));
      expect(documents.state.jobs.length, 25);
      expect(documents.state.nextCursor, isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    documents.setActive(false);
  });
}
