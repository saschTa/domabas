import 'dart:ui' show Tristate;

import 'package:domabas/app/processing_jobs_list.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/email/cubits/email_jobs_cubit.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_jobs_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_email_repository.dart';
import '../support/fake_processing_repository.dart';

void main() {
  testWidgets(
    'exact badges wrap at 320px and 200% with accessible selected chips',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();

      final repository = FakeProcessingRepository()
        ..onJobs = (_, _) async => DocumentProcessingJobPage(
          items: [],
          counts: {
            ('ingestion', 'succeeded'): 123456789,
            ('ingestion', 'failed'): 5,
            ('ai', 'failed'): 42,
          },
        );
      final documents = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: false,
      )..setActive(true);
      final email = EmailJobsCubit(FakeEmailRepository(), allowed: false);
      final paperless = PaperlessJobsCubit(null, allowed: false);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
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
        ),
      );
      await tester.pumpAndSettle();
      final all = find.byKey(const Key('pipeline-filter-all'));
      expect(
        find.descendant(of: all, matching: find.text('123456836')),
        findsOneWidget,
      );
      final node = tester.getSemantics(all).getSemanticsData();
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.hasAction(SemanticsAction.tap), isTrue);
      expect(node.label, contains('123456836 jobs'));
      final document = find.byKey(const Key('pipeline-filter-document'));
      await tester.ensureVisible(document);
      await tester.tap(document);
      await tester.pumpAndSettle();
      final failed = find.byKey(const Key('job-filter-failed'));
      expect(
        find.descendant(of: failed, matching: find.text('5')),
        findsOneWidget,
      );
      await tester.ensureVisible(failed);
      await tester.tap(failed);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: document, matching: find.text('5')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      await documents.close();
      await email.close();
      await paperless.close();
    },
  );
}
