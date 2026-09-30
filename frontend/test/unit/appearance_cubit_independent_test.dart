import 'dart:async';

import 'package:domabas/domain/appearance/models/appearance_preference.dart';
import 'package:domabas/presentation/appearance/cubits/appearance_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_appearance_repository.dart';

const _deadline = Duration(milliseconds: 20);
const _expired = Duration(milliseconds: 21);

void main() {
  testWidgets(
    'restore never writes and explicit System fences a delayed read',
    (tester) async {
      final read = Completer<AppearancePreference>();
      final repository = FakeAppearanceRepository()..onRead = () => read.future;
      final cubit = AppearanceCubit(repository, operationTimeout: _deadline);
      addTearDown(cubit.close);
      cubit.restore();
      cubit.restore();
      await tester.pump();
      expect(repository.reads, 1);
      expect(repository.writes, isEmpty);
      expect(cubit.state.preference, AppearancePreference.system);
      cubit.select(AppearancePreference.system);
      await tester.pump();
      read.complete(AppearancePreference.dark);
      await tester.pump();
      expect(cubit.state.preference, AppearancePreference.system);
      expect(repository.writes, [AppearancePreference.system]);
      expect(cubit.state.restoring, isFalse);
      expect(cubit.state.issue, isNull);
    },
  );

  testWidgets(
    'expired restore rejects late success and permits one fresh retry',
    (tester) async {
      final read = Completer<AppearancePreference>();
      final repository = FakeAppearanceRepository()..onRead = () => read.future;
      final cubit = AppearanceCubit(repository, operationTimeout: _deadline);
      addTearDown(cubit.close);
      cubit.restore();
      await tester.pump(_expired);
      expect(cubit.state.restoring, isFalse);
      expect(cubit.state.issue, AppearanceIssue.restorePending);
      expect(cubit.state.canRetry, isFalse);
      cubit.retry();
      cubit.restore();
      await tester.pump();
      expect(repository.reads, 1);
      read.complete(AppearancePreference.dark);
      await tester.pump();
      expect(cubit.state.preference, AppearancePreference.system);
      expect(cubit.state.issue, AppearanceIssue.restoreUnavailable);
      expect(cubit.state.canRetry, isTrue);
      repository.onRead = () async => AppearancePreference.light;
      cubit.retry();
      await tester.pump();
      expect(repository.reads, 2);
      expect(repository.writes, isEmpty);
      expect(cubit.state.preference, AppearancePreference.light);
      expect(cubit.state.issue, isNull);
    },
  );

  testWidgets(
    'failed restore retries reading until an explicit choice is made',
    (tester) async {
      final repository = FakeAppearanceRepository()
        ..onRead = () async => throw const AppearanceStorageFailure();
      final cubit = AppearanceCubit(repository, operationTimeout: _deadline);
      addTearDown(cubit.close);
      cubit.restore();
      await tester.pump();
      expect(cubit.state.issue, AppearanceIssue.restoreUnavailable);
      expect(cubit.state.canRetry, isTrue);
      repository.onRead = () async => AppearancePreference.dark;
      cubit.retry();
      await tester.pump();
      expect(cubit.state.preference, AppearancePreference.dark);
      expect(repository.writes, isEmpty);
    },
  );

  testWidgets('a hung restore cannot block choosing, writing or disposal', (
    tester,
  ) async {
    final read = Completer<AppearancePreference>();
    final repository = FakeAppearanceRepository()..onRead = () => read.future;
    final cubit = AppearanceCubit(repository, operationTimeout: _deadline);
    cubit.restore();
    await tester.pump(_expired);
    cubit.select(AppearancePreference.dark);
    await tester.pump();
    expect(repository.stored, AppearancePreference.dark);
    expect(cubit.state.issue, isNull);
    await cubit.close();
    read.completeError(const AppearanceStorageFailure());
    await tester.pump();
    expect(repository.reads, 1);
    expect(repository.writes, [AppearancePreference.dark]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid selection coalesces to the latest while only one write runs',
    (tester) async {
      final pending = <Completer<void>>[];
      final repository = FakeAppearanceRepository()
        ..onWrite = (_) {
          final operation = Completer<void>();
          pending.add(operation);
          return operation.future;
        };
      final cubit = AppearanceCubit(repository, operationTimeout: _deadline);
      addTearDown(cubit.close);
      cubit.select(AppearancePreference.dark);
      cubit.select(AppearancePreference.light);
      cubit.select(AppearancePreference.system);
      await tester.pump();
      expect(repository.writes, [AppearancePreference.dark]);
      expect(cubit.state.preference, AppearancePreference.system);
      pending[0].complete();
      await tester.pump();
      expect(repository.writes, [
        AppearancePreference.dark,
        AppearancePreference.system,
      ]);
      expect(cubit.state.saving, isTrue);
      expect(repository.maximumActiveWrites, 1);
      pending[1].complete();
      await tester.pump();
      expect(repository.stored, AppearancePreference.system);
      expect(cubit.state.saving, isFalse);
      expect(cubit.state.issue, isNull);
    },
  );

  testWidgets(
    'write deadline retains lock and old failure drains latest choice',
    (tester) async {
      final pending = <Completer<void>>[];
      final repository = FakeAppearanceRepository()
        ..onWrite = (_) {
          final operation = Completer<void>();
          pending.add(operation);
          return operation.future;
        };
      final cubit = AppearanceCubit(repository, operationTimeout: _deadline);
      addTearDown(cubit.close);
      cubit.select(AppearancePreference.dark);
      await tester.pump(_expired);
      expect(cubit.state.issue, AppearanceIssue.savePending);
      expect(cubit.state.saving, isFalse);
      expect(cubit.state.canRetry, isFalse);
      cubit.retry();
      cubit.select(AppearancePreference.system);
      cubit.select(AppearancePreference.light);
      await tester.pump(_expired);
      expect(repository.writes, [AppearancePreference.dark]);
      expect(cubit.state.issue, AppearanceIssue.savePending);
      pending[0].completeError(const AppearanceStorageFailure());
      await tester.pump();
      expect(repository.writes, [
        AppearancePreference.dark,
        AppearancePreference.light,
      ]);
      expect(cubit.state.preference, AppearancePreference.light);
      expect(cubit.state.saving, isTrue);
      expect(cubit.state.canRetry, isFalse);
      expect(repository.maximumActiveWrites, 1);
      pending[1].complete();
      await tester.pump();
      expect(repository.stored, AppearancePreference.light);
      expect(cubit.state.issue, isNull);
      expect(cubit.state.saving, isFalse);
    },
  );

  testWidgets(
    'old acknowledgement cannot clear newer failure or save its value',
    (tester) async {
      final first = Completer<void>();
      final second = Completer<void>();
      final repository = FakeAppearanceRepository();
      repository.onWrite = (_) =>
          repository.writes.length == 1 ? first.future : second.future;
      final cubit = AppearanceCubit(repository, operationTimeout: _deadline);
      addTearDown(cubit.close);
      cubit.select(AppearancePreference.dark);
      cubit.select(AppearancePreference.light);
      await tester.pump(_expired);
      first.complete();
      await tester.pump();
      expect(cubit.state.saving, isTrue);
      expect(repository.stored, AppearancePreference.dark);
      second.completeError(const AppearanceStorageFailure());
      await tester.pump();
      expect(cubit.state.preference, AppearancePreference.light);
      expect(cubit.state.issue, AppearanceIssue.saveUnavailable);
      expect(cubit.state.canRetry, isTrue);
      expect(repository.stored, AppearancePreference.dark);
      repository.onWrite = (_) async {};
      cubit.retry();
      await tester.pump();
      expect(repository.writes, [
        AppearancePreference.dark,
        AppearancePreference.light,
        AppearancePreference.light,
      ]);
      expect(repository.stored, AppearancePreference.light);
      expect(cubit.state.issue, isNull);
    },
  );

  testWidgets('late restore failure cannot replace a selected write failure', (
    tester,
  ) async {
    final read = Completer<AppearancePreference>();
    final repository = FakeAppearanceRepository();
    repository.onRead = () => read.future;
    repository.onWrite = (_) async => throw const AppearanceStorageFailure();
    final cubit = AppearanceCubit(repository, operationTimeout: _deadline);
    addTearDown(cubit.close);
    cubit.restore();
    cubit.select(AppearancePreference.light);
    await tester.pump();
    read.completeError(const AppearanceStorageFailure());
    await tester.pump();
    expect(cubit.state.issue, AppearanceIssue.saveUnavailable);
    repository.onWrite = (_) async {};
    cubit.retry();
    await tester.pump();
    expect(repository.reads, 1);
    expect(repository.writes, [
      AppearancePreference.light,
      AppearancePreference.light,
    ]);
    expect(cubit.state.issue, isNull);
  });

  for (final fail in [false, true]) {
    testWidgets(
      'dispose fences pending intent after late write ${fail ? 'failure' : 'success'}',
      (tester) async {
        final write = Completer<void>();
        final repository = FakeAppearanceRepository()
          ..onWrite = (_) => write.future;
        final cubit = AppearanceCubit(repository, operationTimeout: _deadline);
        final states = <AppearanceState>[];
        final subscription = cubit.stream.listen(states.add);
        cubit.select(AppearancePreference.dark);
        cubit.select(AppearancePreference.light);
        await tester.pump();
        var closed = false;
        unawaited(cubit.close().then((_) => closed = true));
        await tester.pump();
        expect(
          closed,
          isTrue,
          reason: 'Disposal must not await the platform write.',
        );
        final count = states.length;
        if (fail) {
          write.completeError(const AppearanceStorageFailure());
        } else {
          write.complete();
        }
        await tester.pump(_expired);
        expect(states, hasLength(count));
        expect(repository.writes, [AppearancePreference.dark]);
        expect(repository.activeWrites, 0);
        expect(tester.takeException(), isNull);
        unawaited(subscription.cancel());
        await tester.pump();
      },
    );
  }
}
