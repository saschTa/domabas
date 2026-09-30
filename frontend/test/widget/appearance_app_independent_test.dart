import '../support/workspace_navigation.dart';

import 'dart:async';

import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/domabas_app.dart';
import 'package:domabas/domain/appearance/models/appearance_preference.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas/presentation/appearance/cubits/appearance_cubit.dart';
import 'package:domabas/presentation/appearance/widgets/appearance_action.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_appearance_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';

final class _AppFixture {
  final appearance = FakeAppearanceRepository();
  final auth = FakeAuthRepository();
  final realtime = FakeRealtimeRepository();
  final documents = FakeDocumentRepository();
  final identity = FakeIdentityRepository();
  int authenticated = 0;
  int disposed = 0;

  Widget build() => DomabasApp(
    appearance: appearance,
    auth: auth,
    authenticate: (_, _) {
      authenticated++;
      return AuthenticatedDependencies(
        documents: documents,
        identity: identity,
        email: FakeEmailRepository(),
        activity: FakeActivityRepository(),
        processing: FakeProcessingRepository(),
        realtime: realtime,
        externalLinks: FakeExternalLinkLauncher(),
        close: () => disposed++,
      );
    },
  );
}

Future<void> _openAppearance(WidgetTester tester) async {
  await revealWorkspaceAction(tester, 'appearance-action');
  final action = find.byKey(const Key('appearance-action')).last;
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _choose(
  WidgetTester tester,
  String id, {
  bool close = true,
}) async {
  await _openAppearance(tester);
  await tester.tap(find.byKey(Key('appearance-$id')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  if (close) {
    await tester.tap(find.byKey(const Key('closeAppearance')));
    await tester.pumpAndSettle();
  }
}

ThemeData _themeAt(WidgetTester tester, Finder finder) =>
    Theme.of(tester.element(finder));

void main() {
  testWidgets(
    'explicit modes preserve auth form and System follows brightness without writes',
    (tester) async {
      final fixture = _AppFixture();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final email = find.byKey(const Key('authEmail'));
      final password = find.byKey(const Key('authPassword'));
      await tester.enterText(email, 'draft@example.test');
      await tester.enterText(password, 'unsubmitted password');
      final originalController = tester.widget<TextFormField>(email).controller;
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await _choose(tester, 'dark');
      expect(_themeAt(tester, email).brightness, Brightness.dark);
      expect(
        tester.widget<TextFormField>(email).controller,
        same(originalController),
      );
      expect(originalController!.text, 'draft@example.test');
      expect(
        tester.widget<TextFormField>(password).controller!.text,
        'unsubmitted password',
      );
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(_themeAt(tester, email).brightness, Brightness.dark);
      await _choose(tester, 'light');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(_themeAt(tester, email).brightness, Brightness.light);
      await _choose(tester, 'system');
      expect(_themeAt(tester, email).brightness, Brightness.dark);
      final writes = fixture.appearance.writes.length;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(_themeAt(tester, email).brightness, Brightness.light);
      expect(fixture.appearance.writes, hasLength(writes));
      expect(fixture.appearance.reads, 1);
      expect(fixture.authenticated, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'dark restoration and auth failure use descendant theme and live accessibility',
    (tester) async {
      final restoring = Completer<AuthSession?>();
      final fixture = _AppFixture();
      fixture.appearance.stored = AppearancePreference.dark;
      fixture.auth.onRestore = () => restoring.future;
      await tester.pumpWidget(fixture.build());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final title = find.text('Opening your library…');
      expect(title, findsOneWidget);
      expect(_themeAt(tester, title).brightness, Brightness.dark);
      expect(
        tester.widget<Text>(title).style?.color,
        AppTheme.dark().textTheme.titleLarge!.color,
      );
      expect(find.byKey(const Key('appearance-action')), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .themeAnimationStyle,
        AnimationStyle.noAnimation,
      );
      restoring.completeError(
        const IdentityFailure(IdentityFailureKind.unavailable),
      );
      await tester.pumpAndSettle();
      final failed = find.text('Reconnect to your library');
      expect(failed, findsOneWidget);
      expect(_themeAt(tester, failed).brightness, Brightness.dark);
      expect(
        tester.widget<Text>(failed).style?.color,
        AppTheme.dark().textTheme.titleLarge!.color,
      );
      await _choose(tester, 'light');
      expect(failed, findsOneWidget);
      expect(_themeAt(tester, failed).brightness, Brightness.light);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pump();
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .themeAnimationStyle!
            .duration,
        const Duration(milliseconds: 200),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'initial-password choice retains entered values and authenticated scope',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = _AppFixture();
      fixture.auth.saved = testSession(mustChangePassword: true);
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final current = find.byKey(const Key('currentPassword'));
      final next = find.byKey(const Key('newPassword'));
      await tester.ensureVisible(current);
      await tester.pumpAndSettle();
      await tester.enterText(current, 'current password');
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.enterText(next, 'new draft password');
      final controller = tester.widget<TextFormField>(next).controller;
      await revealWorkspaceAction(tester, 'appearance-action');
      final action = find.byKey(const Key('appearance-action'));
      await revealWorkspaceAction(tester, 'logout');
      final logout = find.byKey(const Key('logout'));
      expect(action.hitTestable(), findsOneWidget);
      expect(logout.hitTestable(), findsOneWidget);
      expect(tester.getRect(action).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(logout).right, lessThanOrEqualTo(320));
      await _openAppearance(tester);
      final dark = find.byKey(const Key('appearance-dark'));
      await tester.ensureVisible(dark);
      await tester.pumpAndSettle();
      await tester.tap(dark);
      await tester.pumpAndSettle();
      final done = find.byKey(const Key('closeAppearance'));
      await tester.ensureVisible(done);
      await tester.pumpAndSettle();
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(find.text('Change initial password'), findsOneWidget);
      expect(tester.widget<TextFormField>(next).controller, same(controller));
      expect(controller!.text, 'new draft password');
      expect(
        tester.widget<TextFormField>(current).controller!.text,
        'current password',
      );
      expect(fixture.authenticated, 1);
      expect(fixture.disposed, 0);
      expect(fixture.appearance.reads, 1);
      expect(logout.hitTestable(), findsOneWidget);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('authEmail')), findsOneWidget);
      expect(
        _themeAt(tester, find.byKey(const Key('authEmail'))).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.disposed, 1);
    },
  );

  testWidgets(
    'same appearance dialog updates pending, failure and retry without focus reset',
    (tester) async {
      final operations = <Completer<void>>[];
      final repository = FakeAppearanceRepository()
        ..onWrite = (_) {
          final operation = Completer<void>();
          operations.add(operation);
          return operation.future;
        };
      final cubit = AppearanceCubit(
        repository,
        operationTimeout: const Duration(milliseconds: 20),
      );
      await tester.pumpWidget(
        BlocBuilder<AppearanceCubit, AppearanceState>(
          bloc: cubit,
          builder: (_, state) => MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.preference == AppearancePreference.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: Scaffold(body: AppearanceAction(cubit: cubit)),
          ),
        ),
      );
      await _openAppearance(tester);
      final dialog = find.byKey(const Key('appearanceDialog'));
      final route = ModalRoute.of(tester.element(dialog));
      final element = tester.element(dialog);
      await tester.tap(find.byKey(const Key('appearance-dark')));
      await tester.pump();
      expect(find.text('Saving appearance…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 21));
      expect(find.textContaining('still waiting'), findsOneWidget);
      expect(find.byKey(const Key('retryAppearance')), findsNothing);
      final focus = FocusManager.instance.primaryFocus;
      operations.first.completeError(const AppearanceStorageFailure());
      await tester.pump();
      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('appearance-action'), skipOffstage: false),
            )
            .tooltip,
        contains('could not be saved'),
      );
      expect(find.byKey(const Key('retryAppearance')), findsOneWidget);
      expect(ModalRoute.of(tester.element(dialog)), same(route));
      expect(tester.element(dialog), same(element));
      expect(FocusManager.instance.primaryFocus, same(focus));
      await tester.tap(find.byKey(const Key('retryAppearance')));
      await tester.pump();
      expect(find.text('Saving appearance…'), findsOneWidget);
      operations.last.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appearanceStatus')), findsNothing);
      expect(tester.element(dialog), same(element));
      expect(repository.writes, [
        AppearancePreference.dark,
        AppearancePreference.dark,
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      final action = tester.widget<IconButton>(
        find.byKey(const Key('appearance-action')),
      );
      expect(action.focusNode!.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );

  testWidgets(
    '320px doubled text keeps appearance choices and workspace controls reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = _AppFixture();
      fixture.auth.saved = testSession(
        extraPermissions: [
          IdentityPermission.connectRealtime,
          IdentityPermission.readOwnActivity,
        ],
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final connects = fixture.realtime.connectCalls;
      await revealWorkspaceAction(tester, 'appearance-action');
      final action = find.byKey(const Key('appearance-action'));
      expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      expect(
        tester.getRect(find.byKey(const Key('librarySwitcher'))).right,
        lessThanOrEqualTo(320),
      );
      await _openAppearance(tester);
      await tester.ensureVisible(find.byKey(const Key('appearance-dark')));
      await tester.tap(find.byKey(const Key('appearance-dark')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('appearance-dark')))
            .selected,
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const Key('closeAppearance')));
      await tester.tap(find.byKey(const Key('closeAppearance')));
      await tester.pumpAndSettle();
      expect(fixture.authenticated, 1);
      expect(fixture.disposed, 0);
      expect(fixture.realtime.connectCalls, connects);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'short 320px enlarged header scroll reaches appearance and sign out',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = _AppFixture();
      fixture.auth.saved = testSession(
        extraPermissions: [
          IdentityPermission.connectRealtime,
          IdentityPermission.readOwnActivity,
        ],
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await revealWorkspaceAction(tester, 'newDocument');
      final primary = find.byKey(const Key('newDocument'));
      await tester.ensureVisible(primary);
      await tester.pumpAndSettle();
      expect(primary.hitTestable(), findsOneWidget);
      await _openAppearance(tester);
      final dark = find.byKey(const Key('appearance-dark'));
      await tester.ensureVisible(dark);
      await tester.pumpAndSettle();
      expect(dark.hitTestable(), findsOneWidget);
      await tester.tap(dark);
      await tester.pumpAndSettle();
      final done = find.byKey(const Key('closeAppearance'));
      await tester.ensureVisible(done);
      await tester.pumpAndSettle();
      await tester.tap(done);
      await tester.pumpAndSettle();
      await revealWorkspaceAction(tester, 'logout');
      final logout = find.byKey(const Key('logout'));
      await tester.ensureVisible(logout);
      await tester.pumpAndSettle();
      expect(logout.hitTestable(), findsOneWidget);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('authEmail')), findsOneWidget);
      expect(
        _themeAt(tester, find.byKey(const Key('authEmail'))).brightness,
        Brightness.dark,
      );
      expect(fixture.appearance.reads, 1);
      expect(fixture.appearance.writes, [AppearancePreference.dark]);
      expect(fixture.disposed, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [390.0, 900.0]) {
    testWidgets(
      'retained navigation chooser at width $width follows system theme',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final fixture = _AppFixture();
        fixture.auth.saved = testSession();
        await tester.pumpWidget(fixture.build());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('navigation-user-settings')));
        await tester.pumpAndSettle();
        final item = find.byKey(const Key('manageLibraries')).last;
        final route = ModalRoute.of(tester.element(item));
        Color visibleSurface() => tester
            .widgetList<Material>(
              find.ancestor(of: item, matching: find.byType(Material)),
            )
            .firstWhere(
              (material) => material.color != null && material.color!.a == 1,
            )
            .color!;
        final before = visibleSurface();
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expect(ModalRoute.of(tester.element(item)), same(route));
        expect(_themeAt(tester, item).brightness, Brightness.dark);
        expect(visibleSurface(), isNot(before));
        expect(visibleSurface().computeLuminance(), lessThan(.15));
        expect(fixture.appearance.writes, isEmpty);
        expect(fixture.authenticated, 1);
        expect(fixture.disposed, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'retained document creation dialog follows system without replacing form',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final fixture = _AppFixture();
      fixture.auth.saved = testSession();
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await revealWorkspaceAction(tester, 'newDocument');
      await tester.tap(find.byKey(const Key('newDocument')));
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('documentTitle'));
      await tester.enterText(title, 'Unsaved new document');
      final controller = tester.widget<TextFormField>(title).controller;
      final route = ModalRoute.of(tester.element(title));
      Material dialogSurface() => tester
          .widgetList<Material>(
            find.ancestor(of: title, matching: find.byType(Material)),
          )
          .firstWhere((material) => material.type == MaterialType.card);
      final oldSurface = dialogSurface().color;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(ModalRoute.of(tester.element(title)), same(route));
      expect(tester.widget<TextFormField>(title).controller, same(controller));
      expect(controller!.text, 'Unsaved new document');
      expect(dialogSurface().color, AppTheme.dark().colorScheme.surface);
      expect(dialogSurface().color, isNot(oldSurface));
      expect(fixture.appearance.writes, isEmpty);
      expect(fixture.authenticated, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
