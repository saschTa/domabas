import 'dart:async';

import 'package:domabas/domain/document/interfaces/document_processing_repository.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/document/cubits/document_processing_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_processing_repository.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  for (final lateFailure in [false, true]) {
    test(
      'namespace replacement cancels old reindex and ignores late ${lateFailure ? 'failure' : 'success'}',
      () async {
        final response = Completer<DocumentReindexBatch>();
        final oldRepository = _LifetimeRepository()
          ..onNamespaceCreate = (_) => response.future;
        final old = DocumentProcessingCubit(
          oldRepository,
          canReadJobs: true,
          canReindex: true,
          requestId: () => 'old-scope-request',
        );
        old.setActive(true);
        await _flush();
        final pending = old.requestReindex();
        expect(oldRepository.namespaceRequests, hasLength(1));
        await old.close();
        await _flush();
        expect(oldRepository.namespaceWriteCancelled, isTrue);
        final replacementRepository = _LifetimeRepository();
        final replacement = DocumentProcessingCubit(
          replacementRepository,
          canReadJobs: true,
          canReindex: true,
          requestId: () => 'new-scope-request',
        );
        addTearDown(replacement.close);
        replacement.setActive(true);
        await _flush();
        final protectedState = old.state;
        if (lateFailure) {
          response.completeError(
            const DocumentProcessingFailure(
              DocumentProcessingFailureKind.unavailable,
            ),
          );
        } else {
          response.complete(testReindexBatch(id: 'old-scope-request'));
        }
        await pending;
        await old.requestReindex(retry: true);
        expect(identical(old.state, protectedState), isTrue);
        expect(oldRepository.namespaceRequests, hasLength(1));
        expect(replacement.state.batches, isEmpty);
        expect(replacement.state.pendingRequest, isNull);
        expect(replacement.state.notice, isNull);
        expect(replacementRepository.namespaceRequests, isEmpty);
        await replacement.requestReindex();
        expect(
          replacementRepository.namespaceRequests.single.id,
          'new-scope-request',
        );
      },
    );
  }

  test('settings logout cancels an uncertain write without publishing or replaying it', () async {
    final response = Completer<DocumentProcessingConfiguration>();
    final repository = _LifetimeRepository()
      ..onUpdate = (_, _, _) => response.future;
    final cubit = DocumentProcessingSettingsCubit(
      repository,
      FakeExternalLinkLauncher(),
      allowed: true,
    );
    cubit.setActive(true);
    await _flush();
    cubit.edit(language: 'deu');
    final save = cubit.save();
    expect(repository.settingWrites, 1);
    await cubit.close();
    await _flush();
    expect(repository.settingsWriteCancelled, isTrue);
    final closedState = cubit.state;
    response.complete(
      DocumentProcessingConfiguration(
        pipeline: testPipeline(revision: 2, language: 'deu'),
      ),
    );
    await save;
    await cubit.save();
    await cubit.requestReindex();
    expect(repository.settingWrites, 1);
    expect(repository.systemRequests, isEmpty);
    expect(identical(cubit.state, closedState), isTrue);
    expect(cubit.state.configuration!.pipeline.configuration.revision, 1);
  });

  testWidgets(
    'realtime refresh never overlaps a read and stops in the background',
    (tester) async {
      final first = Completer<DocumentProcessingPipeline>();
      final second = Completer<DocumentProcessingPipeline>();
      final repository = _LifetimeRepository();
      var reads = 0;
      repository.onPipeline = () => switch (++reads) {
        1 => first.future,
        2 => second.future,
        _ => Future.value(testPipeline()),
      };
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: false,
      );
      cubit.setActive(true);
      await tester.pump(const Duration(seconds: 10));
      expect(repository.pipelineReads, 1);
      await cubit.load(poll: true);
      expect(repository.pipelineReads, 1);
      cubit.invalidate();
      first.complete(testPipeline());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.pipelineReads, 2);
      await tester.pump(const Duration(seconds: 10));
      expect(repository.pipelineReads, 2);
      cubit.setActive(false);
      await tester.pump();
      expect(repository.pipelineCancellations, 1);
      second.complete(testPipeline(revision: 99));
      await tester.pump(const Duration(seconds: 10));
      expect(cubit.state.pipeline!.configuration.revision, 1);
      expect(repository.pipelineReads, 2);
      cubit.setActive(true);
      await tester.pump();
      expect(repository.pipelineReads, 3);
      await cubit.close();
      await tester.pump(const Duration(seconds: 10));
      expect(repository.pipelineReads, 3);
    },
  );

  test('dashboard launch occurs synchronously in allowed gesture and ignores late result after disposal', () async {
    final uri = Uri.parse('https://temporal.internal.example/');
    final repository = _LifetimeRepository()
      ..systemConfiguration = DocumentProcessingConfiguration(
        pipeline: testPipeline(),
        dashboardUrl: uri,
      );
    final launcher = _DeferredLauncher();
    final cubit = DocumentProcessingSettingsCubit(
      repository,
      launcher,
      allowed: true,
    );
    cubit.setActive(true);
    await _flush();
    final launch = cubit.openDashboard();
    expect(launcher.opened, [uri]);
    await cubit.close();
    final closedState = cubit.state;
    launcher.response.complete(false);
    await launch;
    expect(identical(cubit.state, closedState), isTrue);
    await cubit.openDashboard();
    expect(launcher.opened, hasLength(1));
    final denied = DocumentProcessingSettingsCubit(
      repository,
      launcher,
      allowed: false,
    );
    addTearDown(denied.close);
    denied.setActive(true);
    await denied.load();
    await denied.openDashboard();
    expect(denied.state.configuration, isNull);
    expect(launcher.opened, hasLength(1));
  });
}

final class _LifetimeRepository extends FakeProcessingRepository {
  bool namespaceWriteCancelled = false, settingsWriteCancelled = false;
  int settingWrites = 0, pipelineCancellations = 0;
  @override
  Future<DocumentProcessingPipeline> getNamespacePipeline({
    Future<void>? cancel,
  }) {
    if (cancel != null) unawaited(cancel.then((_) => pipelineCancellations++));
    return super.getNamespacePipeline(cancel: cancel);
  }

  @override
  Future<DocumentReindexBatch> createNamespaceBatch(
    DocumentReindexRequest request, {
    Future<void>? cancel,
  }) {
    if (cancel != null) {
      unawaited(cancel.then((_) => namespaceWriteCancelled = true));
    }
    return super.createNamespaceBatch(request, cancel: cancel);
  }

  @override
  Future<DocumentProcessingConfiguration> updateSystemConfiguration({
    required String language,
    required String segmentation,
    int? expectedRevision,
    DocumentLLMSettingsDraft? llm,
    Future<void>? cancel,
  }) {
    settingWrites++;
    if (cancel != null) {
      unawaited(cancel.then((_) => settingsWriteCancelled = true));
    }
    return super.updateSystemConfiguration(
      language: language,
      segmentation: segmentation,
      expectedRevision: expectedRevision,
      llm: llm,
      cancel: cancel,
    );
  }
}

final class _DeferredLauncher implements ExternalLinkLauncher {
  final opened = <Uri>[];
  final response = Completer<bool>();
  @override
  Future<bool> open(Uri uri) {
    opened.add(uri);
    return response.future;
  }
}
