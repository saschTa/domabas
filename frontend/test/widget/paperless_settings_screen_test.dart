import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_settings_cubit.dart';
import 'package:domabas/presentation/paperless/views/paperless_settings_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_paperless_settings_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);

  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<void> mountWorkspace(
    WidgetTester tester,
    FakePaperlessSettingsRepository repository, {
    required bool administrator,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AccountWorkspace(
          session: testSession(
            role: AccountRole.admin,
            extraPermissions: [
              if (administrator) IdentityPermission.managePaperless,
            ],
          ),
          dependencies: AuthenticatedDependencies(
            realtime: FakeRealtimeRepository(),
            email: FakeEmailRepository(),
            activity: FakeActivityRepository(),
            documents: FakeDocumentRepository(),
            identity: FakeIdentityRepository(),
            processing: FakeProcessingRepository(),
            paperlessSettings: repository,
            externalLinks: FakeExternalLinkLauncher(),
            close: () {},
          ),
          onLogout: () {},
          onSessionEnded: (_) {},
          onSwitch: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'system permission exposes settings without namespace import permission',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final repository = FakePaperlessSettingsRepository();
      await mountWorkspace(tester, repository, administrator: true);
      expect(find.byKey(const Key('paperlessNavigation')), findsNothing);
      expect(repository.reads, 0);
      await navigateWorkspace(
        tester,
        'managePaperless',
        group: 'Admin settings',
      );
      expect(find.text('Parallel retrievals'), findsOneWidget);
      await revealWorkspaceContent(
        tester,
        find.text('Shared worker capacity'),
        scrollable: find.descendant(
          of: find.byKey(const Key('paperlessSettingsScroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Shared worker capacity'), findsOneWidget);
      expect(repository.reads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('namespace owners cannot see or load administrator settings', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final repository = FakePaperlessSettingsRepository();
    await mountWorkspace(tester, repository, administrator: false);
    expect(find.byKey(const Key('managePaperless')), findsNothing);
    expect(find.byKey(const Key('navigation-admin-settings')), findsNothing);
    expect(repository.reads, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('saves selected parallelism at ${size.width}px', (
      tester,
    ) async {
      viewport(tester, size);
      final repository = FakePaperlessSettingsRepository();
      final cubit = PaperlessSettingsCubit(repository, allowed: true)
        ..setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: PaperlessSettingsScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('savePaperlessSettings')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.pumpAndSettle();
      await revealWorkspaceContent(
        tester,
        find.byKey(const Key('savePaperlessSettings')),
        scrollable: find.descendant(
          of: find.byKey(const Key('paperlessSettingsScroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const Key('savePaperlessSettings')));
      await tester.pumpAndSettle();
      expect(repository.writes.single, (concurrency: 4, revision: 1));
      expect(find.text('Paperless retrieval settings saved.'), findsOneWidget);
      expect(
        find.text('Currently saved: 4 parallel retrievals.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    });
  }
}
