import 'dart:async';

import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/document/cubits/document_processing_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_processing_repository.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  testWidgets(
    'a status selected during reindex submission loads after the write',
    (tester) async {
      final pending = Completer<DocumentReindexBatch>();
      final repository = FakeProcessingRepository()
        ..jobs = [testProcessingJob(id: 'failed', status: 'failed')]
        ..onNamespaceCreate = (_) => pending.future;
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: true,
      )..setActive(true);
      await tester.pump();
      final save = cubit.requestReindex();
      cubit.filter('failed');
      expect(cubit.state.jobs, isEmpty);
      pending.complete(testReindexBatch());
      await save;
      await tester.pump(const Duration(milliseconds: 300));
      expect(cubit.state.jobs.single.id, 'failed');
      await cubit.close();
    },
  );

  test(
    'changing job status resets history and rejects the old pending page',
    () async {
      final repository = FakeProcessingRepository();
      final requests = <(String?, String?)>[];
      final pending = Completer<DocumentProcessingJobPage>();
      repository.onJobs = (cursor, status) async {
        requests.add((cursor, status));
        if (cursor != null) return pending.future;
        return DocumentProcessingJobPage(
          items: [
            testProcessingJob(
              id: status ?? 'queued',
              status: status ?? 'queued',
            ),
          ],
          nextCursor: '${status ?? 'all'}-next',
        );
      };
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: false,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await flush();
      final more = cubit.load(moreJobs: true);
      await flush();
      cubit.filter('failed');
      await flush();
      expect(requests.last, (null, 'failed'));
      expect(cubit.state.jobs.single.id, 'failed');
      expect(cubit.state.browsingHistory, isFalse);
      pending.complete(
        DocumentProcessingJobPage(items: [testProcessingJob(id: 'stale')]),
      );
      await more;
      expect(cubit.state.jobs.single.id, 'failed');
      cubit.filter('succeeded');
      await flush();
      expect(requests.last, (null, 'succeeded'));
      expect(cubit.state.nextCursor, 'succeeded-next');
      await cubit.load(poll: true);
      expect(requests.last, (null, 'succeeded'));
    },
  );

  test(
    'filtered history removes completed rows and retains selected detail',
    () async {
      final repository = FakeProcessingRepository();
      var completed = false;
      repository.onJobs = (cursor, status) async => DocumentProcessingJobPage(
        items: [
          if (!completed)
            testProcessingJob(
              id: cursor == null ? 'first' : 'older',
              status: 'running',
            ),
        ],
        nextCursor: cursor == null ? 'jobs-page-2' : 'jobs-page-3',
      );
      repository.onJob = (id) async => testProcessingJob(
        id: id,
        status: completed ? 'succeeded' : 'running',
      );
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: true,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await flush();
      cubit.filter('running');
      await flush();
      await cubit.load(moreJobs: true);
      await cubit.selectJob('older');
      expect(cubit.state.jobs.map((job) => job.id), ['first', 'older']);
      completed = true;
      await cubit.load(poll: true);
      expect(cubit.state.jobs, isEmpty);
      expect(cubit.state.selected!.id, 'older');
      expect(cubit.state.selected!.status, 'succeeded');
      expect(cubit.state.nextCursor, 'jobs-page-3');
      expect(cubit.state.browsingHistory, isTrue);
    },
  );

  test('a draft already saved by another administrator becomes the new editing baseline', () async {
    final repository = FakeProcessingRepository();
    final cubit = DocumentProcessingSettingsCubit(
      repository,
      FakeExternalLinkLauncher(),
      allowed: true,
    );
    addTearDown(cubit.close);
    cubit.setActive(true);
    await flush();
    cubit.edit(language: 'deu');
    repository.pipeline = testPipeline(revision: 2, language: 'deu');
    await cubit.load(poll: true);
    expect(cubit.state.dirty, isFalse);
    expect(cubit.state.draftRevision, isNull);
    cubit.edit(language: 'eng');
    expect(cubit.state.draftRevision, 2);
  });

  test('older pages and selected detail survive polling and independent pagination', () async {
    final repository = FakeProcessingRepository();
    var completed = false;
    repository.onJobs = (cursor, status) async => DocumentProcessingJobPage(
      items: [
        testProcessingJob(
          id: cursor == null ? 'first' : 'older',
          status: completed ? 'succeeded' : 'running',
        ),
      ],
      nextCursor: cursor == null ? 'jobs-page-2' : 'jobs-page-3',
    );
    repository.onJob = (id) async =>
        testProcessingJob(id: id, status: completed ? 'succeeded' : 'running');
    repository.onNamespaceBatches = (cursor) async => DocumentReindexBatchPage(
      items: [testReindexBatch(id: cursor == null ? 'batch-1' : 'batch-2')],
      nextCursor: cursor == null ? 'batches-page-2' : null,
    );
    repository.namespaceBatches = [
      testReindexBatch(id: 'batch-1'),
      testReindexBatch(id: 'batch-2'),
    ];
    final cubit = DocumentProcessingCubit(
      repository,
      canReadJobs: true,
      canReindex: true,
    );
    addTearDown(cubit.close);
    cubit.setActive(true);
    await flush();
    await cubit.load(moreJobs: true);
    await cubit.load(moreBatches: true);
    expect(cubit.state.jobs.map((job) => job.id), ['first', 'older']);
    expect(cubit.state.batches, hasLength(2));
    await cubit.selectJob('older');
    completed = true;
    await cubit.load(poll: true);
    expect(cubit.state.jobs.map((job) => job.id), ['first', 'older']);
    expect(cubit.state.jobs.every((job) => job.status == 'succeeded'), isTrue);
    expect(cubit.state.selected!.status, 'succeeded');
    expect(cubit.state.nextCursor, 'jobs-page-3');
    expect(cubit.state.batches, hasLength(2));
    expect(cubit.state.browsingHistory, isTrue);
    await cubit.load();
    expect(cubit.state.jobs.single.id, 'first');
    expect(cubit.state.browsingHistory, isFalse);
  });

  test(
    'uncertain reindex retry preserves UUID and accepted revision',
    () async {
      final repository = FakeProcessingRepository();
      var calls = 0;
      repository.onNamespaceCreate = (request) async {
        if (++calls == 1) {
          throw const DocumentProcessingFailure(
            DocumentProcessingFailureKind.unavailable,
          );
        }
        return testReindexBatch(
          id: request.id,
          revision: request.configurationRevision,
        );
      };
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: true,
        requestId: () => 'stable',
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await flush();
      await cubit.requestReindex();
      expect(cubit.state.pendingRequest!.id, 'stable');
      repository.pipeline = testPipeline(revision: 2);
      await cubit.load();
      await cubit.requestReindex(retry: true);
      expect(
        repository.namespaceRequests.map(
          (request) => (request.id, request.configurationRevision),
        ),
        [('stable', 1), ('stable', 1)],
      );
      expect(cubit.state.pendingRequest, isNull);
      expect(cubit.state.batches.single.id, 'stable');
    },
  );

  test(
    'inactive page ignores delayed results and does not poll or mutate',
    () async {
      final pending = Completer<DocumentProcessingPipeline>();
      final repository = FakeProcessingRepository()
        ..onPipeline = () => pending.future;
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: true,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      cubit.setActive(false);
      pending.complete(testPipeline());
      await flush();
      await cubit.requestReindex();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cubit.state.pipeline, isNull);
      expect(repository.pipelineReads, 1);
      expect(repository.namespaceRequests, isEmpty);
    },
  );

  test('namespace capabilities independently gate jobs and reindex', () async {
    final repository = FakeProcessingRepository()
      ..onJobs = (_, _) async => throw StateError('jobs must not be read');
    final cubit = DocumentProcessingCubit(
      repository,
      canReadJobs: false,
      canReindex: true,
    );
    addTearDown(cubit.close);
    cubit.setActive(true);
    await flush();
    await cubit.selectJob('forbidden');
    await cubit.requestReindex();
    expect(repository.namespaceRequests, hasLength(1));
    expect(cubit.state.jobs, isEmpty);
  });

  test('settings timeout requires readback and never replays a save', () async {
    final repository = FakeProcessingRepository();
    var writes = 0;
    repository.onUpdate = (language, segmentation, revision) async {
      writes++;
      expect(revision, 1);
      repository.systemConfiguration = DocumentProcessingConfiguration(
        pipeline: testPipeline(
          revision: 2,
          language: language,
          segmentation: segmentation,
        ),
      );
      throw const DocumentProcessingFailure(
        DocumentProcessingFailureKind.unavailable,
      );
    };
    final cubit = DocumentProcessingSettingsCubit(
      repository,
      FakeExternalLinkLauncher(),
      allowed: true,
    );
    addTearDown(cubit.close);
    cubit.setActive(true);
    await flush();
    cubit.edit(language: 'deu');
    await cubit.save();
    expect(cubit.state.reconcileRequired, isTrue);
    expect(cubit.canSave, isFalse);
    await cubit.save();
    expect(writes, 1);
    await cubit.load();
    expect(cubit.state.reconcileRequired, isFalse);
    expect(cubit.state.dirty, isFalse);
    expect(cubit.state.configuration!.pipeline.configuration.revision, 2);
    expect(writes, 1);
  });

  test(
    'concurrent settings poll preserves draft precondition and system history',
    () async {
      final repository = FakeProcessingRepository();
      repository.onSystemBatches = (cursor) async => DocumentReindexBatchPage(
        items: [testReindexBatch(id: cursor ?? 'first', scope: 'system')],
        nextCursor: cursor == null ? 'second' : 'third',
      );
      repository.systemBatches = [
        testReindexBatch(id: 'first', scope: 'system'),
        testReindexBatch(id: 'second', scope: 'system'),
      ];
      final cubit = DocumentProcessingSettingsCubit(
        repository,
        FakeExternalLinkLauncher(),
        allowed: true,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await flush();
      await cubit.load(more: true);
      cubit.edit(language: 'deu');
      repository.pipeline = testPipeline(revision: 2, language: 'eng');
      await cubit.load(poll: true);
      expect(cubit.state.batches.map((batch) => batch.id), ['first', 'second']);
      expect(cubit.state.nextCursor, 'third');
      expect(cubit.state.language, 'deu');
      expect(cubit.state.draftRevision, 1);
      repository.onUpdate = (_, _, revision) async {
        expect(revision, 1);
        throw const DocumentProcessingFailure(
          DocumentProcessingFailureKind.conflict,
        );
      };
      await cubit.save();
      expect(cubit.state.error, contains('Processing changed'));
      cubit.resetDraft();
      expect(cubit.state.language, 'eng');
      expect(cubit.state.draftRevision, isNull);
    },
  );
}
