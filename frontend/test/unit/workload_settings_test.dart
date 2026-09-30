import 'dart:async';

import 'package:domabas/domain/workload/models/workload_settings.dart';
import 'package:domabas/presentation/workload/cubits/workload_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_workload_settings_repository.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('only system authority can load or change resource limits', () async {
    final repository = FakeWorkloadSettingsRepository();
    final cubit = WorkloadSettingsCubit(repository, allowed: false);
    cubit.setActive(true);
    await cubit.load();
    cubit.edit('worker', '10');
    await cubit.save();
    expect(repository.reads, 0);
    expect(repository.writes, isEmpty);
    await cubit.close();
  });

  test('positive whole-number bounds and immutable resource mappings', () {
    final settings = testWorkloadSettings(activeOllama: 10);
    final resource = settings.resources[1];
    for (final draft in ['', '0', '-1', '1.5', '65', '1e1', '+2']) {
      expect(resource.validateLimit(draft), isNotNull, reason: draft);
    }
    expect(resource.validateLimit('64'), isNull);
    expect(resource.activeJobs, greaterThan(resource.limit));
    expect(() => settings.resources.clear(), throwsUnsupportedError);
    expect(
      () => settings.pipelines.first.resourceIds.clear(),
      throwsUnsupportedError,
    );
  });

  test('saves the shared resource set with the loaded revision', () async {
    final repository = FakeWorkloadSettingsRepository()
      ..current = testWorkloadSettings(revision: 5);
    final cubit = WorkloadSettingsCubit(repository, allowed: true)
      ..setActive(true);
    await settle();
    cubit.edit('ollama', '65');
    expect(cubit.state.canSave, isFalse);
    cubit.edit('ollama', '12');
    expect(cubit.state.canSave, isTrue);
    await cubit.save();
    expect(repository.writes.single.limits, {
      'worker': 4,
      'ollama': 12,
      'provider:abc': 2,
    });
    expect(repository.writes.single.revision, 5);
    expect(cubit.state.settings!.revision, 6);
    expect(cubit.state.dirty, isFalse);
    expect(cubit.state.notice, 'Workload limits saved.');
    await cubit.close();
  });

  for (final code in ['conflict', 'unavailable']) {
    test('$code retains edits and requires reconciliation', () async {
      final repository = FakeWorkloadSettingsRepository();
      final cubit = WorkloadSettingsCubit(repository, allowed: true)
        ..setActive(true);
      await settle();
      cubit.edit('worker', '12');
      repository.onWrite = () async => throw WorkloadSettingsFailure(code);
      await cubit.save();
      expect(cubit.state.requiresRefresh, isTrue);
      await cubit.save();
      expect(repository.writes, hasLength(1));
      repository.current = testWorkloadSettings(revision: 7, workerLimit: 3);
      await cubit.load();
      expect(cubit.state.drafts['worker'], '12');
      expect(cubit.state.settings!.resources.first.limit, 3);
      expect(cubit.state.canSave, isTrue);
      repository.onWrite = null;
      await cubit.save();
      expect(repository.writes.last.revision, 7);
      await cubit.close();
    });
  }

  test(
    'refresh preserves invalid drafts when a resource ceiling changes',
    () async {
      final repository = FakeWorkloadSettingsRepository();
      final cubit = WorkloadSettingsCubit(repository, allowed: true)
        ..setActive(true);
      await settle();
      cubit.edit('worker', '');
      cubit.edit('ollama', '12');
      repository.current = testWorkloadSettings(
        revision: 2,
        ollamaLimit: 4,
        ollamaMaximum: 6,
      );
      await cubit.load();
      expect(cubit.state.drafts['worker'], '');
      expect(cubit.state.drafts['ollama'], '12');
      expect(cubit.state.canSave, isFalse);
      cubit.resetDraft();
      expect(cubit.state.drafts['ollama'], '4');
      expect(cubit.state.dirty, isFalse);
      await cubit.close();
    },
  );

  test('close cancels the read and ignores late results', () async {
    final result = Completer<WorkloadSettings>();
    final repository = FakeWorkloadSettingsRepository()
      ..onRead = () => result.future;
    final cubit = WorkloadSettingsCubit(repository, allowed: true)
      ..setActive(true);
    final cancelled = repository.lastCancel;
    await cubit.close();
    await cancelled;
    result.complete(testWorkloadSettings());
    await settle();
    expect(cubit.state.settings, isNull);
  });
}
