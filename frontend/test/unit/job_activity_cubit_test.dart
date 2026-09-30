import 'dart:async';

import 'package:domabas/app/job_activity_cubit.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/domain/realtime/models/realtime.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_processing_repository.dart';
import '../support/fake_email_repository.dart';

JobActivityCubit monitor(
  FakeProcessingRepository repository, {
  bool allowed = true,
}) => JobActivityCubit(
  processing: repository,
  email: FakeEmailRepository(),
  canReadJobs: allowed,
  canReadBatches: allowed,
  canReadSystemBatches: allowed,
  canReadEmail: false,
  canReadPaperless: false,
);
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  testWidgets(
    'server totals clear a thousand completed jobs after one hint with no polling',
    (tester) async {
      final repository = FakeProcessingRepository();
      var queued = true, reads = 0;
      repository.onJobs = (cursor, status) async {
        reads++;
        expectSync(status, isNull);
        return DocumentProcessingJobPage(
          counts: {('ingestion', queued ? 'queued' : 'succeeded'): 1000},
          items: queued
              ? List.generate(
                  20,
                  (i) => testProcessingJob(id: 'job-$i', status: 'queued'),
                )
              : [],
          nextCursor: queued ? 'older' : null,
        );
      };
      final cubit = monitor(repository)..setActive(true);
      await tester.pump();
      expect(cubit.state.items.length, 20);
      expect(cubit.state.queuedCount, 1000);
      expect(cubit.state.hasMore, isTrue);
      expect(reads, 1);
      await tester.pump(const Duration(minutes: 5));
      expect(reads, 1);
      queued = false;
      cubit.invalidate({RealtimeTopic.processing});
      await tester.pump(const Duration(milliseconds: 300));
      expect(cubit.state.queuedCount, 0);
      expect(cubit.state.items, isEmpty);
      expect(reads, 2);
      cubit.setRealtimeHealthy(false);
      await tester.pump(const Duration(minutes: 5));
      expect(reads, 2);
      expect(cubit.state.stale, isTrue);
      await cubit.close();
    },
  );

  test(
    'queued to running replaces records without duplicate identities',
    () async {
      final repository = FakeProcessingRepository()
        ..jobs = List.generate(
          20,
          (i) => testProcessingJob(id: 'job-$i', status: 'queued'),
        );
      final cubit = monitor(repository)..setActive(true);
      addTearDown(cubit.close);
      await flush();
      repository.jobs = List.generate(
        20,
        (i) => testProcessingJob(id: 'job-$i'),
      );
      await cubit.refresh();
      expect(cubit.state.items.length, 20);
      expect(cubit.state.runningCount, 20);
      expect(cubit.state.queuedCount, 0);
      expect(cubit.state.items.map((item) => item.id).toSet().length, 20);
    },
  );

  test('pagination retains the loaded window and refreshes every older active record', () async {
    final repository = FakeProcessingRepository();
    var finished = false;
    final cursors = <String?>[];
    repository.onJobs = (cursor, _) async {
      cursors.add(cursor);
      return DocumentProcessingJobPage(
        counts: {('ingestion', 'running'): finished ? 1 : 10},
        items: cursor == null
            ? [testProcessingJob(id: 'latest')]
            : finished
            ? []
            : List.generate(9, (i) => testProcessingJob(id: 'old-$i')),
        nextCursor: cursor == null ? 'older' : null,
      );
    };
    repository.namespaceBatches = [testReindexBatch(id: 'library')];
    repository.systemBatches = [
      testReindexBatch(id: 'system', scope: 'system'),
    ];
    final cubit = monitor(repository)..setActive(true);
    addTearDown(cubit.close);
    await flush();
    await cubit.loadMore();
    expect(cubit.state.items.length, 12);
    expect(cubit.state.batchCount, 2);
    finished = true;
    await cubit.refresh();
    expect(
      cubit.state.items.map((item) => item.id),
      containsAll(['latest', 'library', 'system']),
    );
    expect(cubit.state.items.length, 3);
    expect(cursors, [null, 'older', null, 'older']);
    expect(cubit.state.hasMore, isFalse);
  });

  test('a slow batch source does not block document updates', () async {
    final repository = FakeProcessingRepository()..jobs = [testProcessingJob()];
    final cubit = monitor(repository)..setActive(true);
    addTearDown(cubit.close);
    await flush();
    final pending = Completer<DocumentReindexBatchPage>();
    repository.onNamespaceBatches = (_) => pending.future;
    repository.jobs = [testProcessingJob(status: 'succeeded')];
    final refresh = cubit.refresh();
    await flush();
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.runningCount, 0);
    expect(cubit.state.loading, isTrue);
    pending.complete(DocumentReindexBatchPage(items: [], counts: {}));
    await refresh;
    expect(cubit.state.loading, isFalse);
  });

  testWidgets('hints during reads are retained and hidden scopes defer reads', (
    tester,
  ) async {
    final repository = FakeProcessingRepository();
    final pending = Completer<DocumentProcessingJobPage>();
    var reads = 0;
    repository.onJobs = (_, _) async {
      if (++reads == 1) return pending.future;
      return DocumentProcessingJobPage(items: [], counts: {});
    };
    final cubit = monitor(repository)..setActive(true);
    cubit.invalidate({RealtimeTopic.processing});
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads, 1);
    pending.complete(
      DocumentProcessingJobPage(
        items: [testProcessingJob()],
        counts: {('ingestion', 'running'): 1},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads, 2);
    expect(cubit.state.runningCount, 0);
    cubit.setActive(false);
    cubit.invalidate({RealtimeTopic.processing});
    await tester.pump(const Duration(minutes: 5));
    expect(reads, 2);
    cubit.setActive(true);
    await tester.pump();
    expect(reads, 3);
    await cubit.close();
  });

  test('failed reads retain totals and recover on explicit refresh', () async {
    final repository = FakeProcessingRepository()..jobs = [testProcessingJob()];
    final cubit = monitor(repository)..setActive(true);
    addTearDown(cubit.close);
    await flush();
    repository.onJobs = (_, _) async => throw const DocumentProcessingFailure(
      DocumentProcessingFailureKind.unavailable,
    );
    await cubit.refresh();
    expect(cubit.state.stale, isTrue);
    expect(cubit.state.runningCount, 1);
    repository.onJobs = null;
    repository.jobs = [];
    await cubit.refresh();
    expect(cubit.state.stale, isFalse);
    expect(cubit.state.runningCount, 0);
    expect(cubit.state.items, isEmpty);
  });

  test(
    'permissions prevent reads and backgrounding rejects late results',
    () async {
      final repository = FakeProcessingRepository();
      var reads = 0;
      final pending = Completer<DocumentProcessingJobPage>();
      repository.onJobs = (_, _) {
        reads++;
        return pending.future;
      };
      final denied = monitor(repository, allowed: false)..setActive(true);
      await flush();
      expect(reads, 0);
      expect(denied.state.runningCount, 0);
      await denied.close();
      final cubit = monitor(repository)..setActive(true);
      await flush();
      expect(reads, 1);
      cubit.setActive(false);
      pending.complete(
        DocumentProcessingJobPage(
          items: [testProcessingJob()],
          counts: {('ingestion', 'running'): 1},
        ),
      );
      await flush();
      expect(cubit.state.items, isEmpty);
      await cubit.close();
    },
  );

  test('completed ingestion leaves its active AI attempt visible', () async {
    final repository = FakeProcessingRepository()
      ..jobs = [
        testProcessingJob(id: 'done', status: 'succeeded'),
        testProcessingJob(id: 'ai', pipeline: 'ai', stage: 'invoicing'),
      ];
    final cubit = monitor(repository)..setActive(true);
    addTearDown(cubit.close);
    await flush();
    expect(cubit.state.items.single.kind, JobActivityKind.ai);
    expect(cubit.state.runningCount, 1);
  });

  test('reindex completion includes every terminal outcome and unknown totals stay unknown', () {
    DocumentReindexBatch batch({
      required bool enumerated,
      int total = 10,
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
      discovered: total,
      waiting: 3,
      running: 1,
      succeeded: 2,
      failed: 1,
      skipped: 2,
      superseded: 1,
    );
    expect(batch(enumerated: false).progress, isNull);
    expect(batch(enumerated: true).finished, 6);
    expect(batch(enumerated: true).progress, .6);
    expect(batch(enumerated: true, total: 0, status: 'succeeded').progress, 1);
  });
}
