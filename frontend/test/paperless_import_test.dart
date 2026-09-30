import 'dart:async';

import 'package:domabas/domain/paperless/models/paperless.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_import_cubit.dart';
import 'package:domabas/presentation/paperless/views/paperless_import_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_paperless_repository.dart';

void main() {
  const connection = PaperlessConnection(
    serverUrl: 'https://paperless.example.test',
    token: 'test-token',
  );
  test(
    'ambiguous starts retain request identity and credentials until reconciled',
    () async {
      final repository = MockPaperlessRepository()
        ..startFailure = const PaperlessFailure('unavailable');
      final cubit = PaperlessImportCubit(
        repository,
        requestId: () => '11111111-1111-4111-8111-111111111111',
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(await cubit.start(connection), false);
      expect(cubit.state.pendingRequest, true);
      repository.startFailure = null;
      expect(
        await cubit.start(
          const PaperlessConnection(serverUrl: 'different', token: 'different'),
        ),
        true,
      );
      expect(repository.requestIds.toSet().length, 1);
      expect(repository.tokens, ['test-token', 'test-token']);
      expect(repository.servers, [connection.serverUrl, connection.serverUrl]);
      expect(cubit.state.pendingRequest, false);
      await cubit.cancelRun(repository.jobs.single.id);
      expect(cubit.state.runs.single.cancelRequested, true);
    },
  );
  test(
    'screen closure cancels reads without cancelling durable jobs',
    () async {
      final pending = Completer<List<PaperlessRun>>();
      final repository = MockPaperlessRepository()
        ..pendingList = pending.future;
      final cubit = PaperlessImportCubit(repository);
      final loading = cubit.load();
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
      await repository.observedCancel;
      pending.complete([paperlessRun()]);
      await loading;
      expect(repository.cancellations, isEmpty);
      expect(cubit.isClosed, true);
    },
  );
  testWidgets(
    'settings queues a background job and reloads stored progress on reopen',
    (tester) async {
      final repository = MockPaperlessRepository();
      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: PaperlessImportScreen(
                repository: repository,
                libraryName: 'Test library',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      await tester.enterText(
        find.byKey(const Key('paperlessServer')),
        'http://192.168.10.25:8000/paperless',
      );
      await tester.enterText(
        find.byKey(const Key('paperlessToken')),
        'test-token',
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('paperlessStart'))),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('paperlessStart')));
      await tester.pumpAndSettle();
      expect(repository.jobs, hasLength(1));
      expect(repository.servers, ['http://192.168.10.25:8000/paperless']);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('paperlessToken')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(repository.cancellations, isEmpty);
      await mount();
      await tester.scrollUntilVisible(
        find.text('Queued'),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('paperlessScroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Queued'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.text('Cancel import')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel import'));
      await tester.pumpAndSettle();
      expect(repository.cancellations, hasLength(1));
      expect(find.text('Cancellation requested'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a fresh installation offers URL and token entry on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MockPaperlessRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaperlessImportScreen(
              repository: repository,
              libraryName: 'A library',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paperlessServer')), findsOneWidget);
      expect(find.byKey(const Key('paperlessToken')), findsOneWidget);
      expect(find.byKey(const Key('paperlessStart')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'invalid connection input is explained before any job is submitted',
    () async {
      final repository = MockPaperlessRepository();
      final cubit = PaperlessImportCubit(repository);
      addTearDown(cubit.close);
      await cubit.load();
      for (final server in [
        '',
        'paperless.local',
        'ftp://paperless.local',
        'https://user:password@paperless.local',
        'https://paperless.local?token=secret',
        'https://paperless.local#fragment',
        'https://paperless.local:99999',
        'https://paperless.local:abc',
        'https://paperless.local:/',
        'https://paperless.local/%2e%2e/other',
      ]) {
        expect(
          await cubit.start(
            PaperlessConnection(serverUrl: server, token: 'token'),
          ),
          false,
          reason: server,
        );
        expect(cubit.state.error, contains('server URL'));
        expect(cubit.state.pendingRequest, false);
      }
      for (final token in ['', 'has a space', 'token\nheader', 'ü']) {
        expect(
          await cubit.start(
            PaperlessConnection(serverUrl: connection.serverUrl, token: token),
          ),
          false,
        );
        expect(cubit.state.error, contains('API token'));
      }
      expect(repository.requestIds, isEmpty);
    },
  );
  testWidgets('changing user scope clears the previous connection and jobs', (
    tester,
  ) async {
    final alice = MockPaperlessRepository()..jobs = [paperlessRun()];
    final bob = MockPaperlessRepository();
    Future<void> mount(String user, MockPaperlessRepository repository) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaperlessImportScreen(
              key: ValueKey(user),
              repository: repository,
              libraryName: '$user library',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount('Alice', alice);
    await tester.enterText(
      find.byKey(const Key('paperlessServer')),
      'https://alice.example.test',
    );
    await tester.enterText(
      find.byKey(const Key('paperlessToken')),
      'alice-token',
    );
    await mount('Bob', bob);
    for (final key in ['paperlessServer', 'paperlessToken']) {
      expect(
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text,
        isEmpty,
      );
    }
    expect(find.text('Queued'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('paperlessServer')),
      'https://bob.example.test',
    );
    await tester.enterText(
      find.byKey(const Key('paperlessToken')),
      'bob-token',
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('paperlessStart'))),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paperlessStart')));
    await tester.pumpAndSettle();
    expect(bob.servers, ['https://bob.example.test']);
    expect(bob.tokens, ['bob-token']);
    expect(alice.requestIds, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
