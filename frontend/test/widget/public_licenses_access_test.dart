import 'dart:io';

import 'package:domabas/app/domabas_app.dart';
import 'package:domabas/app/native_server_app.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas/presentation/identity/views/auth_screen.dart';
import 'package:domabas/presentation/licenses/views/licenses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_appearance_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_server_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  setUp(rootBundle.clear);

  Future<void> openLicenses(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('publicLicenses')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final cubit = tester
        .widget<LicensesScreen>(find.byType(LicensesScreen))
        .cubit;
    for (
      var attempt = 0;
      attempt < 100 && !cubit.state.loaded && cubit.state.error == null;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(cubit.state.loaded, isTrue);
    await tester.pumpAndSettle();
    expect(cubit.state.error, isNull);
    expect(cubit.state.loaded, isTrue);
    expect(cubit.state.entries.length, greaterThan(700));
  }

  Widget signedOutApp(FakeAuthRepository auth) => DomabasApp(
    auth: auth,
    appearance: FakeAppearanceRepository(),
    authenticate: (_, _) => throw StateError('Licenses must not sign in'),
  );

  testWidgets(
    'signed-out reader loads bundled notices offline and returns to draft',
    (tester) async {
      var networkClients = 0;
      await HttpOverrides.runZoned(
        () async {
          final auth = FakeAuthRepository();
          await tester.pumpWidget(signedOutApp(auth));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('authEmail')),
            'draft@example.test',
          );
          await openLicenses(tester);
          expect(find.text('About Domabas'), findsOneWidget);
          expect(find.text('User settings'), findsNothing);
          await tester.enterText(
            find.byKey(const Key('licenseSearch')),
            'PDFium backend',
          );
          await tester.pumpAndSettle();
          final record = find.byKey(
            const ValueKey('license-extra:pdfium/LICENSE'),
          );
          await revealWorkspaceContent(
            tester,
            record,
            scrollable: find
                .descendant(
                  of: find.byKey(const Key('licensesScroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.tap(record);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('licenseDetails')), findsOneWidget);
          expect(
            find.widgetWithText(
              SelectableText,
              'https://github.com/klippa-app/go-pdfium/tree/v1.20.3',
            ),
            findsWidgets,
          );
          await tester.tap(find.byKey(const Key('closeLicenseDetails')));
          await tester.pumpAndSettle();
          final cubit = tester
              .widget<LicensesScreen>(find.byType(LicensesScreen))
              .cubit;
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(cubit.isClosed, isTrue);
          expect(find.byType(AuthScreen), findsOneWidget);
          expect(
            tester
                .widget<TextFormField>(find.byKey(const Key('authEmail')))
                .controller!
                .text,
            'draft@example.test',
          );
          expect(auth.lastPassword, isNull);
          expect(auth.saved, isNull);
        },
        createHttpClient: (_) {
          networkClients++;
          throw StateError('The license reader must work without networking');
        },
      );
      expect(networkClients, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, scale, keyboard) in [
    (const Size(1280, 900), 1.0, 0.0),
    (const Size(390, 844), 1.0, 300.0),
    (const Size(320, 480), 2.0, 0.0),
    (const Size(320, 480), 2.0, 180.0),
  ]) {
    testWidgets(
      'footer stays usable at ${size.width}px, ${scale}x and keyboard $keyboard',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        tester.view.padding = FakeViewPadding(bottom: keyboard == 0 ? 24 : 0);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(signedOutApp(FakeAuthRepository()));
        await tester.pumpAndSettle();
        final button = find.byKey(const Key('publicLicenses'));
        final bounds = tester.getRect(button);
        expect(bounds.height, greaterThanOrEqualTo(48));
        expect(bounds.right, lessThan(size.width));
        expect(bounds.center.dx, greaterThan(size.width / 2));
        expect(bounds.bottom, lessThanOrEqualTo(size.height - keyboard));
        final formScroll = find.descendant(
          of: find.byType(AuthScreen),
          matching: find.byType(SingleChildScrollView),
        );
        expect(
          tester.getRect(formScroll).bottom,
          lessThanOrEqualTo(bounds.top),
        );
        await tester.ensureVisible(find.byKey(const Key('submitAuth')));
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
        expect(
          find.byKey(const Key('submitAuth')).hitTestable(),
          findsOneWidget,
        );
        await openLicenses(tester);
        expect(find.byType(BackButton).hitTestable(), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'native first-run reader needs no server and preserves address draft',
    (tester) async {
      final servers = FakeServerRepository();
      await tester.pumpWidget(
        NativeServerApp(
          repository: servers,
          appearance: FakeAppearanceRepository(),
          applicationBuilder: (_, _, _) =>
              throw StateError('No server selected'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('serverAddress')),
        'https://draft.example.test',
      );
      await openLicenses(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(servers.checks, isEmpty);
      expect(servers.saves, isEmpty);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('serverAddress')))
            .controller!
            .text,
        'https://draft.example.test',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'session recovery exposes licenses without retrying the offline server',
    (tester) async {
      var restoreCalls = 0;
      final auth = FakeAuthRepository()
        ..onRestore = () async {
          restoreCalls++;
          throw const IdentityFailure(IdentityFailureKind.unavailable);
        };
      await tester.pumpWidget(signedOutApp(auth));
      await tester.pumpAndSettle();
      expect(find.text('Reconnect to your library'), findsOneWidget);
      await openLicenses(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Reconnect to your library'), findsOneWidget);
      expect(restoreCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
