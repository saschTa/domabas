import 'dart:async';

import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/domabas_app.dart';
import 'package:domabas/app/native_server_app.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/server/models/server_address.dart';
import 'package:domabas/domain/server/models/server_failure.dart';
import 'package:domabas/presentation/server/cubits/server_configuration_cubit.dart';
import 'package:domabas/presentation/server/views/server_configuration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_appearance_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';
import '../support/fake_server_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  Future<void> connect(WidgetTester tester, String address) async {
    await tester.enterText(find.byKey(const Key('serverAddress')), address);
    await tester.ensureVisible(find.byKey(const Key('connectServer')));
    await tester.tap(find.byKey(const Key('connectServer')));
    await tester.pumpAndSettle();
  }

  testWidgets('first launch selects a checked server and restart restores it', (
    tester,
  ) async {
    final repository = FakeServerRepository();
    final appearance = FakeAppearanceRepository();
    final built = <String>[];
    Widget app(Key key) => NativeServerApp(
      key: key,
      repository: repository,
      appearance: appearance,
      applicationBuilder: (address, configuration, theme) {
        built.add(address.value);
        return MaterialApp(home: Text(address.value));
      },
    );
    await tester.pumpWidget(app(const ValueKey(1)));
    await tester.pumpAndSettle();
    expect(find.text('Connect to your server'), findsOneWidget);
    expect(built, isEmpty);
    await connect(tester, ' http://192.168.0.230:8088/base/ ');
    expect(built.last, 'http://192.168.0.230:8088/base');
    expect(repository.checks, hasLength(1));
    expect(repository.stored?.value, built.last);
    await tester.pumpWidget(app(const ValueKey(2)));
    await tester.pumpAndSettle();
    expect(find.text('http://192.168.0.230:8088/base'), findsOneWidget);
    expect(repository.checks, hasLength(1));
  });

  testWidgets('failed server check stays on setup with editable address', (
    tester,
  ) async {
    final repository = FakeServerRepository()
      ..onCheck = (_) async =>
          throw const ServerFailure(ServerFailureKind.unreachable);
    await tester.pumpWidget(
      NativeServerApp(
        repository: repository,
        appearance: FakeAppearanceRepository(),
        applicationBuilder: (_, _, _) => const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();
    await connect(tester, 'https://offline.example.com');
    expect(find.textContaining('Could not reach this server'), findsOneWidget);
    expect(repository.stored, isNull);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('serverAddress')))
          .enabled,
      isTrue,
    );
  });

  testWidgets(
    'changing server removes old workspace and preserves endpoint-scoped sessions',
    (tester) async {
      final old = ServerAddress.parse('https://one.example.com');
      final repository = FakeServerRepository()..stored = old;
      final firstAuth = FakeAuthRepository()..saved = testSession();
      final secondAuth = FakeAuthRepository();
      final appearance = FakeAppearanceRepository();
      var scopesClosed = 0;
      await tester.pumpWidget(
        NativeServerApp(
          repository: repository,
          appearance: appearance,
          applicationBuilder: (address, configuration, theme) => DomabasApp(
            appearance: appearance,
            appearanceCubit: theme,
            serverConfiguration: configuration,
            auth: address == old ? firstAuth : secondAuth,
            authenticate: (_, _) => _scope(() => scopesClosed++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account a'), findsWidgets);
      await navigateWorkspace(tester, 'serverNavigation');
      await connect(tester, 'https://two.example.com');
      expect(find.byKey(const Key('authEmail')), findsOneWidget);
      expect(find.text('https://two.example.com'), findsOneWidget);
      expect(find.text('Account a'), findsNothing);
      expect(scopesClosed, 1);
      expect(firstAuth.saved, isNotNull);
      expect(secondAuth.saved, isNull);
      expect(appearance.reads, 1);
      await tester.tap(find.byKey(const Key('configureServer')));
      await tester.pumpAndSettle();
      await connect(tester, old.value);
      expect(find.text('Account a'), findsWidgets);
      expect(find.byKey(const Key('serverAddress')), findsNothing);
      expect(firstAuth.revoked, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(scopesClosed, 2);
    },
  );

  testWidgets('a late restore cannot reopen an old server after replacement', (
    tester,
  ) async {
    final pending = Completer<AuthSession?>();
    final repository = FakeServerRepository()
      ..stored = ServerAddress.parse('https://one.example.com');
    final oldAuth = FakeAuthRepository()
      ..onRestore = () async => await pending.future;
    final appearance = FakeAppearanceRepository();
    var createdScopes = 0;
    await tester.pumpWidget(
      NativeServerApp(
        repository: repository,
        appearance: appearance,
        applicationBuilder: (address, configuration, theme) => DomabasApp(
          appearance: appearance,
          appearanceCubit: theme,
          serverConfiguration: configuration,
          auth: address.value.contains('one.') ? oldAuth : FakeAuthRepository(),
          authenticate: (_, _) {
            createdScopes++;
            return _scope(() {});
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('configureServer')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(
      find.byKey(const Key('serverAddress')),
      'https://two.example.com',
    );
    await tester.tap(find.byKey(const Key('connectServer')));
    await tester.pumpAndSettle();
    pending.complete(testSession());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('authEmail')), findsOneWidget);
    expect(createdScopes, 0);
  });

  testWidgets('web-style composition has no server selection control', (
    tester,
  ) async {
    await tester.pumpWidget(
      DomabasApp(
        appearance: FakeAppearanceRepository(),
        auth: FakeAuthRepository(),
        authenticate: (_, _) => _scope(() {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('authEmail')), findsOneWidget);
    expect(find.byKey(const Key('configureServer')), findsNothing);
  });

  testWidgets(
    'configuration fits narrow screens with large text and validation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cubit = ServerConfigurationCubit(FakeServerRepository());
      await cubit.restore();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: ServerConfigurationScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      await connect(tester, 'not a server');
      expect(find.textContaining('Enter an HTTP or HTTPS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await cubit.close();
    },
  );
}

AuthenticatedDependencies _scope(VoidCallback close) =>
    AuthenticatedDependencies(
      realtime: FakeRealtimeRepository(),
      email: FakeEmailRepository(),
      activity: FakeActivityRepository(),
      processing: FakeProcessingRepository(),
      externalLinks: FakeExternalLinkLauncher(),
      documents: FakeDocumentRepository(),
      identity: FakeIdentityRepository(),
      close: close,
    );
