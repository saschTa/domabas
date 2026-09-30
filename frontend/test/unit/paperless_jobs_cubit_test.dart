import 'dart:async';

import 'package:domabas/domain/paperless/models/paperless.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_jobs_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mock_paperless_repository.dart';

void main() {
  test('filtering restarts pagination, rejects stale reads and separates partial imports', () async {
    final repository = MockPaperlessRepository()
      ..jobs = [
        for (var i = 0; i < 45; i++) paperlessRun(id: 'queued-$i'),
        paperlessRun(id: 'success', state: 'succeeded'),
        paperlessRun(id: 'partial', state: 'succeeded', failed: 1),
      ];
    final cubit = PaperlessJobsCubit(repository, allowed: true)
      ..setActive(true);
    addTearDown(cubit.close);
    await Future<void>.delayed(Duration.zero);
    await cubit.load(more: true);
    expect(cubit.state.browsingHistory, isTrue);
    final pending = Completer<List<PaperlessRun>>();
    repository.pendingList = pending.future;
    final oldRead = cubit.load(more: true);
    repository.pendingList = null;
    cubit.filter('succeeded');
    await Future<void>.delayed(Duration.zero);
    expect(repository.listRequests.last, (null, 'succeeded'));
    expect(cubit.state.runs.single.id, 'success');
    expect(cubit.state.browsingHistory, isFalse);
    pending.complete([paperlessRun(id: 'stale')]);
    await oldRead;
    expect(cubit.state.runs.single.id, 'success');
    cubit.filter('partial');
    await Future<void>.delayed(Duration.zero);
    expect(repository.listRequests.last, (null, 'partial'));
    expect(cubit.state.runs.single.id, 'partial');
    cubit.filter(null);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.runs.length, 20);
    expect(repository.listRequests.last, (null, null));
  });

  test('missing repository and denied access never read imports', () async {
    final repository = MockPaperlessRepository();
    for (final cubit in [
      PaperlessJobsCubit(repository, allowed: false),
      PaperlessJobsCubit(null, allowed: true),
    ]) {
      cubit.setActive(true);
      await cubit.load();
      expect(cubit.allowed, isFalse);
      await cubit.close();
    }
    expect(repository.lists, 0);
  });

  test(
    'hiding cancels reads, ignores late results and resumes fresh reads',
    () async {
      final pending = Completer<List<PaperlessRun>>();
      final repository = MockPaperlessRepository()
        ..pendingList = pending.future;
      final cubit = PaperlessJobsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      var cancelled = false;
      unawaited(repository.observedCancel!.then((_) => cancelled = true));
      cubit.setActive(false);
      pending.complete([paperlessRun(id: 'stale')]);
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      expect(cubit.state.runs, isEmpty);
      repository.pendingList = null;
      repository.jobs = [paperlessRun(id: 'fresh')];
      cubit.setActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.runs.single.id, 'fresh');
    },
  );

  test(
    'selected details refresh outside history and survive a read failure',
    () async {
      final run = paperlessRun(
        id: 'selected',
        state: 'running',
        stage: 'importing',
      );
      final repository = MockPaperlessRepository()..jobs = [run];
      final cubit = PaperlessJobsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.selectJob(run);
      await Future<void>.delayed(Duration.zero);
      repository.jobs = [paperlessRun(id: 'new')];
      repository.details[run.id] = paperlessRun(
        id: run.id,
        state: 'succeeded',
        imported: 1,
      );
      await cubit.load(poll: true);
      expect(cubit.state.selected?.state, 'succeeded');
      expect(cubit.state.runs.single.id, 'new');
      final failed = Completer<List<PaperlessRun>>();
      repository.pendingList = failed.future;
      final read = cubit.load(poll: true);
      failed.completeError(const PaperlessFailure('source_unavailable'));
      await read;
      expect(cubit.state.error, contains('Could not read Paperless'));
      expect(cubit.state.selected?.imported, 1);
      expect(cubit.state.runs.single.id, 'new');
      cubit.clearSelection();
      expect(cubit.state.selected, isNull);
    },
  );

  testWidgets(
    'visible imports refresh on events without polling and stop when hidden',
    (tester) async {
      final repository = MockPaperlessRepository();
      final cubit = PaperlessJobsCubit(repository, allowed: true)
        ..setActive(true);
      await tester.pump();
      expect(repository.lists, 1);
      await tester.pump(const Duration(minutes: 2));
      expect(repository.lists, 1);
      cubit.invalidate();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.lists, 2);
      cubit.setActive(false);
      await tester.pump(const Duration(seconds: 30));
      expect(repository.lists, 2);
      final pending = Completer<List<PaperlessRun>>();
      repository.pendingList = pending.future;
      cubit.setActive(true);
      final cancel = repository.observedCancel!;
      await cubit.close();
      await expectLater(cancel, completes);
      pending.complete([paperlessRun()]);
      await tester.pump(const Duration(seconds: 30));
      expect(repository.lists, 3);
      expect(cubit.state.runs, isEmpty);
    },
  );
}
