import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/workload/cubits/workload_settings_cubit.dart';
import 'package:domabas/presentation/workload/views/workload_settings_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';
import '../support/fake_workload_settings_repository.dart';
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

  Finder field(String id) => find.byWidgetPredicate(
    (widget) =>
        widget is TextFormField &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'workloadLimit-$id-',
        ),
  );

  for (final size in [
    const Size(320, 844),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets(
      'resource limits and pipeline requirements work at ${size.width}px',
      (tester) async {
        viewport(tester, size);
        final repository = FakeWorkloadSettingsRepository()
          ..current = testWorkloadSettings(activeOllama: 10);
        final cubit = WorkloadSettingsCubit(repository, allowed: true)
          ..setActive(true);
        await tester.pumpWidget(
          MaterialApp(
            theme: size.width == 320 ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(size.width == 320 ? 2 : 1),
              ),
              child: child!,
            ),
            home: Scaffold(body: WorkloadSettingsScreen(cubit: cubit)),
          ),
        );
        await tester.pumpAndSettle();
        final scrollable = find
            .descendant(
              of: find.byKey(const Key('workloadSettingsScroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        await revealWorkspaceContent(
          tester,
          field('ollama'),
          scrollable: scrollable,
        );
        await tester.enterText(field('ollama'), '65');
        await tester.pumpAndSettle();
        expect(find.text('Enter a whole number from 1 to 64.'), findsOneWidget);
        expect(cubit.state.canSave, isFalse);
        await tester.enterText(field('ollama'), '12');
        await tester.pumpAndSettle();
        await revealWorkspaceContent(
          tester,
          find.byKey(const Key('saveWorkloadSettings')),
          scrollable: scrollable,
        );
        await tester.tap(find.byKey(const Key('saveWorkloadSettings')));
        await tester.pumpAndSettle();
        expect(repository.writes.single.limits['ollama'], 12);
        expect(repository.writes.single.revision, 1);
        await revealWorkspaceContent(
          tester,
          find.text('What shares these limits'),
          scrollable: scrollable,
        );
        await revealWorkspaceContent(
          tester,
          find.text('AI chat'),
          scrollable: scrollable,
        );
        expect(find.text('Paperless retrieval'), findsOneWidget);
        expect(find.text('Document ingestion'), findsOneWidget);
        expect(find.text('External AI · example.test'), findsWidgets);
        expect(find.text('High priority'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await cubit.close();
      },
    );
  }

  for (final administrator in [false, true]) {
    testWidgets(
      'workload navigation requires its system claim: $administrator',
      (tester) async {
        viewport(tester, const Size(390, 844));
        final repository = FakeWorkloadSettingsRepository();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: AccountWorkspace(
              session: testSession(
                role: AccountRole.admin,
                extraPermissions: [
                  if (administrator) IdentityPermission.manageWorkloads,
                ],
              ),
              dependencies: AuthenticatedDependencies(
                realtime: FakeRealtimeRepository(),
                email: FakeEmailRepository(),
                activity: FakeActivityRepository(),
                documents: FakeDocumentRepository(),
                identity: FakeIdentityRepository(),
                processing: FakeProcessingRepository(),
                workloadSettings: repository,
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
        expect(repository.reads, 0);
        if (administrator) {
          await navigateWorkspace(
            tester,
            'manageWorkloads',
            group: 'Admin settings',
          );
          expect(find.text('Workload limits'), findsWidgets);
          expect(repository.reads, 1);
        } else {
          expect(find.byKey(const Key('manageWorkloads')), findsNothing);
          expect(
            find.byKey(const Key('navigation-admin-settings')),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
