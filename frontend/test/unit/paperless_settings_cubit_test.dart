import 'dart:async';

import 'package:domabas/domain/paperless/models/paperless_settings.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_paperless_settings_repository.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'settings authority is independent and denies all work when absent',
    () async {
      final repository = FakePaperlessSettingsRepository();
      final cubit = PaperlessSettingsCubit(repository, allowed: false);
      cubit.setActive(true);
      await cubit.load();
      cubit.edit(5);
      await cubit.save();
      expect(repository.reads, 0);
      expect(repository.writes, isEmpty);
      await cubit.close();
    },
  );

  test(
    'validates bounds and saves the selected value with its loaded revision',
    () async {
      final repository = FakePaperlessSettingsRepository()
        ..current = testPaperlessSettings(revision: 4);
      final cubit = PaperlessSettingsCubit(repository, allowed: true);
      cubit.setActive(true);
      await settle();
      cubit.edit(0);
      cubit.edit(11);
      expect(cubit.state.retrievalConcurrency, 1);
      expect(cubit.state.canSave, isFalse);
      cubit.edit(10);
      expect(cubit.state.canSave, isTrue);
      await cubit.save();
      expect(repository.writes.single, (concurrency: 10, revision: 4));
      expect(cubit.state.settings!.revision, 5);
      expect(cubit.state.dirty, isFalse);
      expect(cubit.state.notice, isNotNull);
      await cubit.close();
    },
  );

  for (final code in ['conflict', 'unavailable']) {
    test(
      '$code preserves the draft and requires a refresh before another write',
      () async {
        final repository = FakePaperlessSettingsRepository();
        final cubit = PaperlessSettingsCubit(repository, allowed: true);
        cubit.setActive(true);
        await settle();
        cubit.edit(5);
        repository.onWrite = () async => throw PaperlessSettingsFailure(code);
        await cubit.save();
        expect(cubit.state.retrievalConcurrency, 5);
        expect(cubit.state.requiresRefresh, isTrue);
        await cubit.save();
        expect(repository.writes, hasLength(1));
        repository.current = testPaperlessSettings(concurrency: 3, revision: 2);
        await cubit.load();
        expect(cubit.state.retrievalConcurrency, 5);
        expect(cubit.state.settings!.retrievalConcurrency, 3);
        expect(cubit.state.canSave, isTrue);
        repository.onWrite = null;
        await cubit.save();
        expect(repository.writes.last, (concurrency: 5, revision: 2));
        await cubit.close();
      },
    );
  }

  test(
    'returning to settings refreshes the saved value without losing edits',
    () async {
      final repository = FakePaperlessSettingsRepository();
      final cubit = PaperlessSettingsCubit(repository, allowed: true);
      cubit.setActive(true);
      await settle();
      cubit.edit(4);
      cubit.setActive(false);
      repository.current = testPaperlessSettings(concurrency: 2, revision: 3);
      cubit.setActive(true);
      await settle();
      expect(cubit.state.settings!.revision, 3);
      expect(cubit.state.retrievalConcurrency, 4);
      await cubit.close();
    },
  );

  test('close cancels pending work and ignores its late completion', () async {
    final result = Completer<PaperlessSettings>();
    final repository = FakePaperlessSettingsRepository()
      ..onRead = () => result.future;
    final cubit = PaperlessSettingsCubit(repository, allowed: true);
    cubit.setActive(true);
    final cancelled = repository.lastCancel;
    await cubit.close();
    await cancelled;
    result.complete(testPaperlessSettings(concurrency: 8));
    await settle();
    expect(cubit.state.settings, isNull);
  });
}
