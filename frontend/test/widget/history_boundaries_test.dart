import 'package:domabas/app/processing_jobs_list.dart';
import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/email/cubits/email_jobs_cubit.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_jobs_cubit.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_email_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/mock_paperless_repository.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
  testWidgets('unread Paperless pages bound older email and document jobs', (
    tester,
  ) async {
    final imports = MockPaperlessRepository()
      ..jobs = List.generate(
        25,
        (i) => paperlessRun(
          id: 'import-$i',
          state: 'succeeded',
          createdAt: i < 20
              ? DateTime.utc(2026, 9, 19, 23).subtract(Duration(minutes: i))
              : DateTime.utc(2026, 9, 17).subtract(Duration(minutes: i)),
        ),
      );
    final emails = FakeEmailRepository()
      ..runs['email'] = EmailRun(
        id: 'email',
        providerId: 'provider',
        namespaceId: 'library',
        reason: 'manual',
        status: 'succeeded',
        stage: 'complete',
        createdAt: DateTime.utc(2026, 9, 19),
      );
    final documents = DocumentProcessingCubit(
      FakeProcessingRepository()..jobs = [testProcessingJob(id: 'document')],
      canReadJobs: true,
      canReindex: false,
    )..setActive(true);
    final email = EmailJobsCubit(emails, allowed: true)..setActive(true);
    final paperless = PaperlessJobsCubit(imports, allowed: true)
      ..setActive(true);
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
    expect(find.byKey(const Key('email-job-email')), findsNothing);
    expect(find.byKey(const Key('job-document')), findsNothing);
    expect(find.byType(AppRecordRow), findsNWidgets(20));
    final next = find.byKey(const Key('loadMorePipelineJobs'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(paperless.state.runs.length, 25);
    expect(paperless.state.cursor, isNull);
    expect(find.byType(AppRecordRow), findsNWidgets(7));
    final keys = tester
        .widgetList<AppRecordRow>(find.byType(AppRecordRow))
        .map((row) => row.key)
        .toList();
    expect(keys.take(2), [
      const Key('email-job-email'),
      const Key('job-document'),
    ]);
    await tester.ensureVisible(find.text('Previous').first);
    await tester.tap(find.text('Previous').first);
    await tester.pumpAndSettle();
    expect(find.byType(AppRecordRow), findsNWidgets(20));
    expect(imports.lists, 2);
    expect(tester.takeException(), isNull);
    documents.setActive(false);
    email.setActive(false);
    paperless.setActive(false);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
