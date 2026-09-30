import 'dart:async';

import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/domain/paperless/models/paperless.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/email/cubits/email_jobs_cubit.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_jobs_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_email_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/mock_paperless_repository.dart';

final class CountingEmailRepository extends FakeEmailRepository {
  Future<EmailRunPage> Function(String? cursor) read = (_) async =>
      EmailRunPage(items: []);
  @override
  Future<EmailRunPage> listRuns(
    String? providerId, {
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) => read(cursor);
}

EmailRun run(String id) => EmailRun(
  id: id,
  providerId: 'provider',
  namespaceId: 'library',
  reason: 'scheduled',
  status: 'succeeded',
  stage: 'complete',
  createdAt: DateTime.utc(2026),
);
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('state and page count snapshots cannot be changed by callers', () {
    final counts = {'failed': 7};
    final email = EmailJobsState(counts: counts);
    final paperless = PaperlessJobsState(counts: counts);
    final page = EmailRunPage(items: [], counts: counts);
    counts['failed'] = 100;
    expect(email.counts?['failed'], 7);
    expect(paperless.counts?['failed'], 7);
    expect(page.counts?['failed'], 7);
    expect(() => email.counts!['failed'] = 2, throwsUnsupportedError);
    final documents = <(String, String), int>{('ai', 'failed'): 3};
    final state = DocumentProcessingState(counts: documents);
    documents.clear();
    expect(state.counts?[('ai', 'failed')], 3);
  });

  test('email totals refresh in history, retain errors and reject a late filter response', () async {
    final repository = CountingEmailRepository()
      ..read = (cursor) async => EmailRunPage(
        items: [run(cursor == null ? 'first' : 'older')],
        nextCursor: cursor == null ? 'older' : null,
        counts: {'succeeded': 25},
      );
    final cubit = EmailJobsCubit(repository, allowed: true)..setActive(true);
    addTearDown(cubit.close);
    await flush();
    await cubit.load(more: true);
    expect(cubit.state.counts?['succeeded'], 25);
    final pending = Completer<EmailRunPage>();
    repository.read = (_) => pending.future;
    final poll = cubit.load(poll: true);
    expect(cubit.state.countsRefreshing, isTrue);
    expect(cubit.state.counts?['succeeded'], 25);
    pending.complete(
      EmailRunPage(items: [run('new')], counts: {'succeeded': 26}),
    );
    await poll;
    expect(cubit.state.runs.map((r) => r.id), ['first', 'older']);
    expect(cubit.state.browsingHistory, isTrue);
    expect(cubit.state.counts?['succeeded'], 26);
    repository.read = (_) async =>
        throw const EmailFailure(EmailFailureKind.unavailable);
    await cubit.load(poll: true);
    expect(cubit.state.counts?['succeeded'], 26);
    expect(cubit.state.countsError, isTrue);
    expect(cubit.state.countsRefreshing, isFalse);
    final stale = Completer<EmailRunPage>();
    repository.read = (_) => stale.future;
    final read = cubit.load();
    repository.read = (_) async =>
        EmailRunPage(items: [], counts: {'failed': 3});
    cubit.filter('failed');
    await flush();
    stale.complete(EmailRunPage(items: [], counts: {'failed': 999}));
    await read;
    expect(cubit.state.counts?['failed'], 3);
    expect(cubit.state.countsError, isFalse);
  });

  test(
    'document totals survive failed refresh and are fenced with job filters',
    () async {
      final repository = FakeProcessingRepository()
        ..onJobs = (_, _) async => DocumentProcessingJobPage(
          items: [],
          counts: {('ai', 'failed'): 25},
        );
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: false,
      )..setActive(true);
      addTearDown(cubit.close);
      await flush();
      expect(cubit.state.counts?[('ai', 'failed')], 25);
      repository.onJobs = (_, _) async => throw const DocumentProcessingFailure(
        DocumentProcessingFailureKind.unavailable,
      );
      await cubit.load(poll: true);
      expect(cubit.state.counts?[('ai', 'failed')], 25);
      expect(cubit.state.countsError, isTrue);
      final pending = Completer<DocumentProcessingJobPage>();
      repository.onJobs = (_, _) => pending.future;
      final read = cubit.load();
      await flush();
      repository.onJobs = (_, _) async =>
          DocumentProcessingJobPage(items: [], counts: {('ai', 'failed'): 30});
      cubit.filter('failed', pipeline: 'ai');
      await flush();
      pending.complete(
        DocumentProcessingJobPage(items: [], counts: {('ai', 'failed'): 99}),
      );
      await read;
      expect(cubit.state.counts?[('ai', 'failed')], 30);
      expect(cubit.state.countsError, isFalse);
    },
  );

  test(
    'Paperless totals update while preserving older pages and failed evidence',
    () async {
      final repository = MockPaperlessRepository()
        ..counts = {'succeeded': 45, 'partial': 3}
        ..jobs = [
          for (var i = 0; i < 45; i++)
            paperlessRun(id: 'job-$i', state: 'succeeded'),
        ];
      final cubit = PaperlessJobsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await flush();
      await cubit.load(more: true);
      final cursor = cubit.state.cursor;
      repository.counts = {'succeeded': 46, 'partial': 3};
      repository.jobs.insert(0, paperlessRun(id: 'new', state: 'succeeded'));
      await cubit.load(poll: true);
      expect(cubit.state.runs.length, 40);
      expect(cubit.state.runs.first.id, 'job-0');
      expect(cubit.state.cursor, cursor);
      expect(cubit.state.counts?['succeeded'], 46);
      repository.pendingList = Future.error(
        const PaperlessFailure('unavailable'),
      );
      await cubit.load(poll: true);
      expect(cubit.state.countsError, isTrue);
      expect(cubit.state.counts?['succeeded'], 46);
    },
  );
}
