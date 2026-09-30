import 'dart:async';

import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_cubit.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/document_ai_fixture.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_processing_repository.dart';

void main() {
  test(
    'uncertain AI retry retains request identity and searchable ingestion',
    () async {
      final document = documentWithAI();
      final repository = FakeDocumentRepository()..records = [document];
      var ids = 0;
      final cubit = DocumentCubit(
        repository,
        id: document.id,
        capabilities: const DocumentCapabilities(read: true, retry: true),
        onUpdated: (_) {},
        onDeleted: (_) async {},
        requestId: () => 'request-${++ids}',
      );
      addTearDown(cubit.close);
      await cubit.load();
      repository.failure = const DocumentFailure(
        DocumentFailureKind.unavailable,
      );
      await cubit.retryAIProcessing();
      expect(cubit.state.pendingAIRetry?.id, 'request-1');
      expect(cubit.state.document!.processing!.state, 'ready');
      expect(cubit.state.document!.processing!.generation, 7);
      repository.failure = null;
      await cubit.retryAIProcessing();
      expect(repository.aiRetries.map((request) => request.id), [
        'request-1',
        'request-1',
      ]);
      expect(
        repository.aiRetries.map((request) => request.configurationRevision),
        [3, 3],
      );
      expect(ids, 1);
      expect(cubit.state.pendingAIRetry, isNull);
      expect(cubit.state.document!.processing!.generation, 7);
    },
  );

  test(
    'AI retry respects permissions and ignores a response after viewer closes',
    () async {
      final document = documentWithAI();
      final repository = FakeDocumentRepository()..records = [document];
      final readonly = DocumentCubit(
        repository,
        id: document.id,
        capabilities: const DocumentCapabilities(read: true),
        onUpdated: (_) {},
        onDeleted: (_) async {},
      );
      await readonly.load();
      await readonly.retryAIProcessing();
      expect(repository.aiRetries, isEmpty);
      await readonly.close();
      final pending = Completer<DocumentAIProcessing>();
      repository.onRetryAI = (_, _) => pending.future;
      var mutations = 0;
      final cubit = DocumentCubit(
        repository,
        id: document.id,
        capabilities: const DocumentCapabilities(read: true, retry: true),
        onUpdated: (_) {},
        onDeleted: (_) async {},
        onMutation: () async {
          mutations++;
        },
      );
      await cubit.load();
      final retry = cubit.retryAIProcessing();
      await cubit.close();
      pending.complete(document.processing!.ai!);
      await retry;
      expect(mutations, 0);
    },
  );

  test(
    'pipeline change rejects old pages and preserves AI history during polling',
    () async {
      final pending = Completer<DocumentProcessingJobPage>();
      final repository = FakeProcessingRepository();
      var completed = false;
      repository.onPipelineJobs = (cursor, status, pipeline) async {
        if (pipeline == null && cursor != null) return pending.future;
        return DocumentProcessingJobPage(
          items: [
            testProcessingJob(
              id: cursor == null ? '${pipeline ?? 'all'}-first' : 'ai-older',
              pipeline: pipeline ?? 'ingestion',
              stage: 'invoicing',
            ),
          ],
          nextCursor: cursor == null ? 'next' : 'older-next',
        );
      };
      repository.onJob = (id) async => testProcessingJob(
        id: id,
        pipeline: 'ai',
        status: completed ? 'succeeded' : 'running',
        stage: completed ? 'complete' : 'invoicing',
      );
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: false,
      )..setActive(true);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      final oldPage = cubit.load(moreJobs: true);
      await Future<void>.delayed(Duration.zero);
      cubit.filter(null, pipeline: 'ai');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.jobPipeline, 'ai');
      expect(cubit.state.jobs.single.id, 'ai-first');
      pending.complete(
        DocumentProcessingJobPage(items: [testProcessingJob(id: 'obsolete')]),
      );
      await oldPage;
      expect(cubit.state.jobs.single.id, 'ai-first');
      await cubit.load(moreJobs: true);
      await cubit.selectJob('ai-older');
      completed = true;
      await cubit.load(poll: true);
      expect(cubit.state.jobs.map((job) => job.id), ['ai-first', 'ai-older']);
      expect(cubit.state.selected!.status, 'succeeded');
      expect(cubit.state.nextCursor, 'older-next');
      expect(cubit.state.browsingHistory, isTrue);
      expect(repository.jobPipelines.last, 'ai');
    },
  );
}
