import 'workspace_actions.dart'
    show
        revealWorkspaceAction,
        revealWorkspacePageContent,
        waitForWorkspaceWidget;

import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/domabas_app.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/presentation/workload/views/workload_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:domabas/ui/domabas_ui.dart';

import 'document_workspace.dart';
import 'scanner_workflow.dart';
import 'paperless_workflow.dart';
import 'llm_processing.dart';
import 'invoice_workflow.dart';
import 'ai_chat.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'personal and shared libraries preserve roles, claims and system administration',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final email = 'browser-$suffix@example.com';
      final otherEmail = 'browser-other-$suffix@example.com';
      final title = 'E2E document $suffix';
      const password = 'Br0wser!';
      const description =
          'Created through Flutter, the generated API client, Go and PostgreSQL.';
      var dependencies = AppDependencies.production();
      final originalAppearance = await dependencies.appearance.read();
      String? currentSessionToken;
      BrowserScannerFixture? currentScanner;
      addTearDown(() => dependencies.dispose());
      addTearDown(() => dependencies.appearance.write(originalAppearance));

      Future<void> waitForDocumentCollection() async {
        await waitForWorkspaceWidget(
          tester,
          find.byWidgetPredicate(
            (widget) =>
                widget is DocumentsScreen &&
                widget.cubit.state.hasSnapshot &&
                !widget.cubit.state.isLoading,
            description: 'document collection with a completed server snapshot',
          ),
        );
        expect(
          tester
              .widget<DocumentsScreen>(find.byType(DocumentsScreen))
              .cubit
              .state
              .error,
          isNull,
        );
      }

      Future<void> mount() async {
        await tester.pumpWidget(
          DomabasApp(
            appearance: dependencies.appearance,
            auth: dependencies.auth,
            uploads: dependencies.uploads,
            authenticate: (session, onUnauthorized) {
              currentSessionToken = session.token;
              return withScannerFixture(
                dependencies.authenticate(session, onUnauthorized),
                session,
                (scanner) => currentScanner = scanner,
              );
            },
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> authenticate(String address, {String? accountName}) async {
        await waitForWorkspaceWidget(
          tester,
          find.byKey(const Key('authEmail')),
        );
        if (accountName != null) {
          await tester.tap(find.byKey(const Key('switchAuthMode')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('accountName')),
            accountName,
          );
        }
        await tester.enterText(find.byKey(const Key('authEmail')), address);
        await tester.enterText(find.byKey(const Key('authPassword')), password);
        await tester.ensureVisible(find.byKey(const Key('submitAuth')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('submitAuth')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('submitAuth')));
        await tester.pumpAndSettle();
        await waitForWorkspaceWidget(
          tester,
          find.byKey(const Key('currentAccount')),
        );
        expect(find.byKey(const Key('currentAccount')), findsOneWidget);
        await waitForDocumentCollection();
      }

      Future<void> chooseAppearance(String mode) async {
        await revealWorkspaceAction(tester, 'appearance-action');
        await tester.tap(find.byKey(const Key('appearance-action')).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('appearance-$mode')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('closeAppearance')));
        await tester.pumpAndSettle();
      }

      Future<void> openLibrary(
        String name, {
        bool pendingSearch = false,
      }) async {
        final retiringDocuments = pendingSearch
            ? tester.widget<DocumentsScreen>(find.byType(DocumentsScreen)).cubit
            : null;
        await tester.tap(find.byKey(const Key('librarySwitcher')));
        await tester.pumpAndSettle();
        final row = find.descendant(
          of: find.byType(AppDialog),
          matching: find.ancestor(
            of: find.text(name),
            matching: find.byType(AppRecordRow),
          ),
        );
        await tester.ensureVisible(row);
        if (retiringDocuments != null) {
          retiringDocuments.editTerm(
            'pending library $suffix',
            composing: false,
          );
          expect(retiringDocuments.state.debouncing, isTrue);
        }
        await tester.tap(row);
        await tester.pumpAndSettle();
        await waitForWorkspaceWidget(
          tester,
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.key == const Key('currentAccount') &&
                widget.data == name,
          ),
        );
        expect(find.text('Switch library'), findsNothing);
        expect(
          tester.widget<Text>(find.byKey(const Key('currentAccount'))).data,
          name,
        );
        await waitForDocumentCollection();
        if (retiringDocuments != null) {
          expect(retiringDocuments.isClosed, isTrue);
          await tester.pump(const Duration(milliseconds: 400));
          final currentDocuments = tester
              .widget<DocumentsScreen>(find.byType(DocumentsScreen))
              .cubit;
          expect(currentDocuments, isNot(same(retiringDocuments)));
          expect(currentDocuments.state.rawTerm, isEmpty);
          expect(currentDocuments.state.criteria, isNull);
          expect(currentDocuments.state.desiredCriteria.query, isEmpty);
        }
      }

      Future<void> verifyMobileNavigation({
        required bool manageMembers,
        required bool administerSystem,
      }) async {
        tester.view.devicePixelRatio = 1;
        for (final width in [360.0, 390.0]) {
          tester.view.physicalSize = Size(width, 844);
          await tester.pumpAndSettle();
          final surface = find.byKey(const Key('workspaceNotchedNavigation'));
          final circle = find.byKey(const Key('navigationDocumentsCircle'));
          expect(surface, findsOneWidget);
          expect(tester.getSize(circle), const Size(56, 56));
          expect(tester.getCenter(circle).dx, closeTo(width / 2, .01));
          expect(
            tester.getCenter(circle).dy - tester.getTopLeft(surface).dy,
            closeTo(30, .01),
          );
          expect(tester.getSize(surface).height, 92);
        }
        expect(
          find.byKey(const Key('workspaceBottomNavigation')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('openNavigation')), findsNothing);
        expect(find.byKey(const Key('navigation-more')), findsOneWidget);
        await tester.tap(find.byKey(const Key('navigation-more')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('changePassword')), findsOneWidget);
        expect(
          find.byKey(const Key('manageMembers')),
          manageMembers ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('manageInvitations')),
          manageMembers ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('manageWorkloads')),
          administerSystem ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.byKey(const Key('manageLibraries')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('acceptInvitationCode')), findsOneWidget);
        if (administerSystem) {
          await tester.tap(find.byKey(const Key('navigation-more')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('manageSystemUsers')));
          await tester.pumpAndSettle();
          expect(
            find.byWidgetPredicate(
              (widget) => widget is AppPage && widget.title == 'System users',
            ),
            findsOneWidget,
          );
        }
        await tester.tap(find.byKey(const Key('documentsNavigation')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('documentCollectionScroll')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpAndSettle();
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await mount();
      await chooseAppearance('light');
      expect(
        Theme.of(tester.element(find.byKey(const Key('authEmail')))).brightness,
        Brightness.light,
      );
      await chooseAppearance('system');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      await chooseAppearance('dark');
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
      dependencies = AppDependencies.production();
      await mount();
      expect(
        Theme.of(tester.element(find.byKey(const Key('authEmail')))).brightness,
        Brightness.dark,
      );
      await authenticate(email, accountName: 'Browser account A');
      expect(
        Theme.of(tester.element(find.byKey(const Key('currentAccount'))))
            .brightness,
        Brightness.dark,
      );
      await verifyMobileNavigation(manageMembers: true, administerSystem: true);
      await exerciseWorkloadSettings(
        tester,
        remount: () async {
          await tester.pumpWidget(const SizedBox.shrink());
          dependencies.dispose();
          dependencies = AppDependencies.production();
          await mount();
          await waitForDocumentCollection();
        },
      );
      await exercisePaperlessSettings(
        tester,
        (key) => navigateWorkspace(
          tester,
          key,
          group: key == 'managePaperless' ? 'Admin settings' : 'Workspace',
        ),
      );
      expect(find.text('Your library is unavailable'), findsNothing);
      await revealWorkspaceAction(tester, 'newDocument');
      await tester.tap(find.byKey(const Key('newDocument')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('documentTitle')), title);
      await tester.enterText(
        find.byKey(const Key('documentDescription')),
        description,
      );
      await tester.tap(find.byKey(const Key('saveDocument')));
      await tester.pumpAndSettle();
      await waitForWorkspaceWidget(
        tester,
        find.byKey(const Key('saveDocument')),
        present: false,
      );
      await waitForWorkspaceWidget(tester, find.text(title));
      expect(find.text(title), findsOneWidget);

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      await waitForWorkspaceWidget(
        tester,
        find.byKey(const Key('documentDetails')),
      );
      expect(find.byKey(const Key('documentDetails')), findsOneWidget);
      final savedDescription = find.descendant(
        of: find.byKey(const Key('documentInspectorPanel')),
        matching: find.text(description),
      );
      await waitForWorkspaceWidget(tester, savedDescription);
      expect(savedDescription, findsOneWidget);
      await tester.tap(find.byKey(const Key('closeDocument')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
      dependencies = AppDependencies.production();
      await mount();
      expect(find.byKey(const Key('authEmail')), findsNothing);
      await waitForDocumentCollection();
      expect(find.byKey(const Key('currentAccount')), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byKey(const Key('currentAccount'))))
            .brightness,
        Brightness.dark,
      );
      await waitForWorkspaceWidget(tester, find.text(title));
      expect(find.text(title), findsOneWidget);
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      await waitForWorkspaceWidget(tester, savedDescription);
      expect(savedDescription, findsOneWidget);
      await tester.tap(find.byKey(const Key('closeDocument')));
      await tester.pumpAndSettle();

      await navigateWorkspace(tester, 'manageMembers');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inviteMember')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('inviteEmail')), otherEmail);
      await tester.tap(find.byKey(const Key('saveMember')));
      await tester.pumpAndSettle();
      await waitForWorkspaceWidget(
        tester,
        find.byKey(const Key('invitationCode')),
      );
      final invitationCode = tester
          .widget<SelectableText>(find.byKey(const Key('invitationCode')))
          .data!;
      await tester.tap(find.byKey(const Key('closeInvitationCode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invitationCode')), findsNothing);
      await navigateWorkspace(
        tester,
        'documentsNavigation',
        group: 'Workspace',
      );
      await tester.pumpAndSettle();

      final signedOutDocuments = tester
          .widget<DocumentsScreen>(find.byType(DocumentsScreen))
          .cubit;
      await tester.enterText(
        find.byKey(const Key('documentSearchTerm')),
        'pending session $suffix',
      );
      expect(signedOutDocuments.state.debouncing, isTrue);
      await revealWorkspaceAction(tester, 'logout');
      await tester.tap(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      expect(signedOutDocuments.isClosed, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('authEmail')), findsOneWidget);
      expect(find.text(title), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
      dependencies = AppDependencies.production();
      await mount();
      expect(find.byKey(const Key('authEmail')), findsOneWidget);
      await authenticate(otherEmail, accountName: 'Browser account B');
      await verifyMobileNavigation(
        manageMembers: true,
        administerSystem: false,
      );
      expect(find.text(title), findsNothing);
      expect(find.text('No documents yet'), findsOneWidget);
      await navigateWorkspace(tester, 'manageLibraries');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('acceptInvitationCode')),
        invitationCode,
      );
      await tester.ensureVisible(find.byKey(const Key('acceptInvitation')));
      await tester.tap(find.byKey(const Key('acceptInvitation')));
      await tester.pumpAndSettle();
      await waitForWorkspaceWidget(
        tester,
        find.textContaining('Invitation accepted for Browser account A'),
      );
      expect(
        find.textContaining('Invitation accepted for Browser account A'),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('currentAccount'))).data,
        'Browser account B',
      );
      await openLibrary('Browser account A');
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
      dependencies = AppDependencies.production();
      await mount();
      await waitForDocumentCollection();
      expect(
        tester.widget<Text>(find.byKey(const Key('currentAccount'))).data,
        'Browser account A',
      );
      expect(find.text(title), findsOneWidget);
      expect(
        tester
            .widget<AppWorkspaceShell>(find.byType(AppWorkspaceShell))
            .actions
            .where((action) => action.id == 'newDocument'),
        isEmpty,
      );
      expect(find.byKey(const Key('newDocument')), findsNothing);
      expect(find.byKey(const Key('manageMembers')), findsNothing);
      expect(find.byKey(const Key('manageSystemUsers')), findsNothing);
      await verifyMobileNavigation(
        manageMembers: false,
        administerSystem: false,
      );
      await navigateWorkspace(tester, 'manageLibraries');
      await tester.pumpAndSettle();
      await openLibrary('Browser account B');
      expect(find.text(title), findsNothing);
      await revealWorkspaceAction(tester, 'newDocument');
      await tester.tap(find.byKey(const Key('newDocument')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('documentTitle')),
        'Private B $suffix',
      );
      await tester.tap(find.byKey(const Key('saveDocument')));
      await tester.pumpAndSettle();
      await waitForWorkspaceWidget(
        tester,
        find.byKey(const Key('saveDocument')),
        present: false,
      );
      await waitForWorkspaceWidget(tester, find.text('Private B $suffix'));
      expect(find.text('Private B $suffix'), findsOneWidget);
      await revealWorkspaceAction(tester, 'logout');
      await tester.tap(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      await authenticate(email);
      await waitForWorkspaceWidget(tester, find.text(title));
      expect(find.text(title), findsOneWidget);
      expect(find.text('Private B $suffix'), findsNothing);

      await navigateWorkspace(
        tester,
        'manageSystemUsers',
        group: 'Admin settings',
      );
      await tester.pumpAndSettle();
      final systemRow = find.ancestor(
        of: find.text(otherEmail),
        matching: find.byType(AppRecordRow),
      );
      Future<void> changeSystemRole(String action, String role) async {
        final enabledAction = find.ancestor(
          of: find.descendant(of: systemRow, matching: find.text(action)),
          matching: find.byWidgetPredicate(
            (widget) => widget is TextButton && widget.enabled,
          ),
        );
        await waitForWorkspaceWidget(tester, enabledAction);
        await tester.tap(enabledAction);
        await tester.pumpAndSettle();
        await waitForWorkspaceWidget(
          tester,
          find.byKey(const Key('confirmSystemRole')),
        );
        await tester.tap(find.byKey(const Key('confirmSystemRole')));
        await tester.pumpAndSettle();
        await waitForWorkspaceWidget(
          tester,
          find.descendant(of: systemRow, matching: find.text(role)),
        );
      }

      await changeSystemRole('Make admin', 'System admin');
      await changeSystemRole('Remove admin', 'User');
      await navigateWorkspace(
        tester,
        'documentsNavigation',
        group: 'Workspace',
      );
      await tester.pumpAndSettle();

      await exerciseLLMProcessing(
        tester,
        sessionToken: currentSessionToken!,
        navigate: (key) => navigateWorkspace(
          tester,
          key,
          group: key == 'manageDocumentProcessing'
              ? 'Admin settings'
              : 'Workspace',
        ),
      );

      await exerciseInvoiceWorkflow(
        tester,
        sessionToken: currentSessionToken!,
        navigate: (key) => navigateWorkspace(tester, key, group: 'Workspace'),
      );

      await exerciseAIChat(
        tester,
        sessionToken: currentSessionToken!,
        navigate: (key) => navigateWorkspace(
          tester,
          key,
          group: key == 'manageChat' ? 'Admin settings' : 'Workspace',
        ),
        remount: () async {
          await tester.pumpWidget(const SizedBox.shrink());
          dependencies.dispose();
          dependencies = AppDependencies.production();
          await mount();
        },
      );

      await navigateWorkspace(tester, 'manageMembers');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit $otherEmail'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('claim-documents:create')),
      );
      await tester.tap(find.byKey(const Key('claim-documents:create')));
      await tester.tap(find.byKey(const Key('saveMember')));
      await tester.pumpAndSettle();
      await waitForWorkspaceWidget(
        tester,
        find.byKey(const Key('saveMember')),
        present: false,
      );
      await navigateWorkspace(
        tester,
        'documentsNavigation',
        group: 'Workspace',
      );
      await tester.pumpAndSettle();
      await revealWorkspaceAction(tester, 'logout');
      await tester.tap(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      await authenticate(otherEmail);
      expect(find.text('Private B $suffix'), findsOneWidget);
      await navigateWorkspace(tester, 'manageLibraries');
      await tester.pumpAndSettle();
      await openLibrary('Browser account A');
      expect(find.text(title), findsOneWidget);
      expect(find.text('Private B $suffix'), findsNothing);
      await revealWorkspaceAction(tester, 'newDocument');
      expect(find.byKey(const Key('newDocument')), findsOneWidget);
      await tester.tap(find.byTooltip('Close actions'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manageMembers')), findsNothing);
      await openLibrary('Browser account B', pendingSearch: true);
      await exerciseDocumentWorkspace(
        tester,
        sessionToken: currentSessionToken!,
        remount: () async {
          await tester.pumpWidget(const SizedBox.shrink());
          dependencies.dispose();
          dependencies = AppDependencies.production();
          await mount();
        },
      );
      await exerciseScannerWorkflow(tester, () => currentScanner!);
      await exercisePaperlessWorkflow(
        tester,
        (key) => navigateWorkspace(tester, key),
      );
    },
  );
}

Future<void> exerciseWorkloadSettings(
  WidgetTester tester, {
  required Future<void> Function() remount,
}) async {
  Future<void> open() async {
    await navigateWorkspace(tester, 'manageWorkloads', group: 'Admin settings');
    await waitForWorkspaceWidget(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is WorkloadSettingsScreen &&
            widget.cubit.state.settings != null &&
            !widget.cubit.state.loading,
        description: 'workload limits loaded from the server',
      ),
    );
  }

  WorkloadSettingsScreen screen() => tester.widget<WorkloadSettingsScreen>(
    find.byType(WorkloadSettingsScreen),
  );
  Finder workerField() => find.byWidgetPredicate(
    (widget) =>
        widget is TextFormField &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'workloadLimit-worker-',
        ),
  );
  Future<void> reveal(Finder target) => revealWorkspacePageContent(
    tester,
    target,
    list: find.byKey(const Key('workloadSettingsScroll')),
  );

  Future<void> save(int limit) async {
    final cubit = screen().cubit;
    await reveal(workerField());
    await tester.enterText(workerField(), '$limit');
    await tester.pumpAndSettle();
    expect(cubit.state.canSave, isTrue);
    final save = find.byKey(const Key('saveWorkloadSettings'));
    await reveal(save);
    final saveBounds = tester.getRect(save);
    await tester.tap(save);
    await waitForWorkspaceWidget(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is WorkloadSettingsScreen &&
            !widget.cubit.state.saving &&
            widget.cubit.state.notice != null,
        description: 'workload limits saved by the server',
      ),
    );
    expect(cubit.state.error, isNull);
    expect(tester.getRect(save), saveBounds);
    expect(save.hitTestable(), findsOneWidget);
    expect(
      cubit.state.settings!.resources
          .singleWhere((r) => r.id == 'worker')
          .limit,
      limit,
    );
  }

  await open();
  final settings = screen().cubit.state.settings!;
  final worker = settings.resources.singleWhere((r) => r.id == 'worker');
  expect(
    settings.pipelines.singleWhere((p) => p.id == 'paperless').resourceIds,
    ['worker'],
  );
  expect(
    settings.pipelines
        .singleWhere((p) => p.id == 'document_ingestion')
        .resourceIds,
    unorderedEquals(['worker', 'ollama']),
  );
  await reveal(find.text('What shares these limits'));
  final matrix = find.ancestor(
    of: find.text('What shares these limits'),
    matching: find.byType(AppSurface),
  );
  for (final label in [
    'Document ingestion',
    'Paperless imports',
    worker.label,
    settings.resources.singleWhere((r) => r.id == 'ollama').label,
  ]) {
    expect(
      find.descendant(of: matrix, matching: find.text(label)),
      findsWidgets,
    );
  }
  final changedLimit = worker.limit < worker.maximumLimit
      ? worker.limit + 1
      : worker.limit - 1;
  await save(changedLimit);
  await remount();
  await open();
  expect(
    screen().cubit.state.settings!.resources
        .singleWhere((r) => r.id == 'worker')
        .limit,
    changedLimit,
  );
  expect(
    screen().cubit.state.settings!.revision,
    greaterThan(settings.revision),
  );
  await save(worker.limit);
  await navigateWorkspace(tester, 'documentsNavigation', group: 'Workspace');
}

Future<void> navigateWorkspace(
  WidgetTester tester,
  String key, {
  String group = 'User settings',
}) async {
  final destination = find.byKey(Key(key));
  if (destination.evaluate().isEmpty &&
      find
          .byKey(const Key('workspaceBottomNavigation'))
          .evaluate()
          .isNotEmpty) {
    final trigger = find.byKey(
      Key(
        find.byKey(const Key('navigation-more')).evaluate().isNotEmpty
            ? 'navigation-more'
            : group == 'Admin settings'
            ? 'navigation-admin-settings'
            : 'navigation-user-settings',
      ),
    );
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  } else if (destination.evaluate().isEmpty) {
    await tester.tap(find.byTooltip(group));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(destination);
  await tester.pumpAndSettle();
  expect(
    destination.hitTestable(),
    findsOneWidget,
    reason: '$key is visible before navigation.',
  );
  await tester.tap(destination);
  await tester.pumpAndSettle();
}
