import '../support/fake_realtime_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_activity_repository.dart';
import "../support/fake_processing_repository.dart";

import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/ui/app_navigation_button.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_third_party_license_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<void> mount(
    WidgetTester tester, {
    required AuthSession session,
    required FakeIdentityRepository identity,
    FakeDocumentRepository? documents,
    FakeThirdPartyLicenseRepository? licenses,
    double scale = 1,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale), padding: padding),
          child: child!,
        ),
        home: AccountWorkspace(
          session: session,
          dependencies: AuthenticatedDependencies(
            realtime: FakeRealtimeRepository(),
            email: FakeEmailRepository(),
            activity: FakeActivityRepository(),
            processing: FakeProcessingRepository(),
            externalLinks: FakeExternalLinkLauncher(),
            documents: documents ?? FakeDocumentRepository(),
            licenses: licenses ?? FakeThirdPartyLicenseRepository(),
            identity: identity,
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

  for (final (name, role, systemRole) in [
    ('viewer', AccountRole.viewer, SystemRole.user),
    ('namespace manager', AccountRole.admin, SystemRole.user),
    (
      'system administrator without namespace management',
      AccountRole.viewer,
      SystemRole.admin,
    ),
  ]) {
    testWidgets('$name reaches only authorized mobile destinations', (
      tester,
    ) async {
      viewport(tester, const Size(390, 844));
      var members = 0;
      var invitations = 0;
      var accounts = 0;
      var users = 0;
      final identity = FakeIdentityRepository()
        ..onList = () async {
          members++;
          return MemberPage(items: [], total: 0);
        }
        ..onInvitations = () async {
          invitations++;
          return InvitationPage(items: [], total: 0);
        }
        ..onAccounts = () async {
          accounts++;
          return AccountPage(items: [], total: 0);
        }
        ..onSystemUsers = (_, _) async {
          users++;
          return SystemUserPage(items: [], total: 0, adminCount: 0);
        };
      await mount(
        tester,
        session: testSession(role: role, systemRole: systemRole),
        identity: identity,
      );
      expect(
        find.byKey(const Key('workspaceBottomNavigation')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('openNavigation')), findsNothing);
      expect(find.byKey(const Key('navigation-admin-settings')), findsNothing);

      final select = tester
          .widget<AppWorkspaceShell>(find.byType(AppWorkspaceShell))
          .onSelected;
      select('unknown-destination');
      if (role != AccountRole.admin) {
        select('members');
        select('invitations');
      }
      if (systemRole != SystemRole.admin) select('system-users');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppWorkspaceShell>(find.byType(AppWorkspaceShell))
            .selectedId,
        'documents',
      );
      expect((members, invitations, accounts, users), (0, 0, 0, 0));

      await tester.tap(find.byKey(const Key('navigation-more')));
      await tester.pumpAndSettle();
      expect(find.text('a@example.com'), findsOneWidget);
      expect(
        find.byKey(const Key('manageMembers')),
        role == AccountRole.admin ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('manageInvitations')),
        role == AccountRole.admin ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.byKey(const Key('manageLibraries')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('acceptInvitationCode')), findsOneWidget);
      expect(accounts, 1);
      select('libraries');
      await tester.pumpAndSettle();
      expect(accounts, 1);
      expect(
        tester
            .widget<AppNavigationButton>(
              find.byKey(const Key('navigation-more')),
            )
            .selected,
        isTrue,
      );
      if (role == AccountRole.admin) {
        await navigateWorkspace(tester, 'manageMembers');
        expect(find.byKey(const Key('inviteMember')), findsOneWidget);
        expect((members, invitations), (1, 1));
      }
      if (systemRole == SystemRole.admin) {
        await navigateWorkspace(
          tester,
          'manageSystemUsers',
          group: 'Admin settings',
        );
        expect(
          find.byWidgetPredicate(
            (widget) => widget is AppPage && widget.title == 'System users',
          ),
          findsOneWidget,
        );
        expect(users, 1);
        expect((members, invitations), (0, 0));
      }
      await navigateWorkspace(tester, 'licensesNavigation');
      expect(find.byKey(const Key('licensesScreen')), findsOneWidget);
      expect(find.byKey(const Key('licenseSearch')), findsOneWidget);
      final beforeDisposal = (members, invitations, accounts, users);
      await tester.pumpWidget(const SizedBox.shrink());
      for (final id in [
        'documents',
        'libraries',
        'members',
        'invitations',
        'password',
        'system-users',
        'licenses',
        'unknown',
      ]) {
        select(id);
      }
      await tester.pumpAndSettle();
      expect((members, invitations, accounts, users), beforeDisposal);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'chooser Back preserves settings and later workspace Back returns to documents',
    (tester) async {
      viewport(tester, const Size(390, 844));
      await mount(
        tester,
        session: testSession(),
        identity: FakeIdentityRepository(),
      );
      await navigateWorkspace(tester, 'changePassword');
      expect(find.byKey(const Key('currentPassword')), findsOneWidget);
      await tester.tap(find.byKey(const Key('navigation-more')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('closeNavigationChooser')), findsNothing);
      expect(find.byKey(const Key('currentPassword')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('currentPassword')), findsNothing);
      expect(find.byKey(const Key('documentCount')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, admin) in [(320.0, false), (320.0, true), (390.0, true)]) {
    testWidgets(
      'real actions remain reachable at $width by 320, 2x text, admin $admin and safe padding',
      (tester) async {
        viewport(tester, Size(width, 320));
        final documents = FakeDocumentRepository()
          ..records = List.generate(
            DocumentsCubit.pageSize + 1,
            (index) => Document(
              id: '$index',
              title: 'Document $index',
              description: '',
              createdAt: DateTime.utc(2026),
            ),
          );
        await mount(
          tester,
          session: testSession(
            systemRole: admin ? SystemRole.admin : SystemRole.user,
          ),
          identity: FakeIdentityRepository(),
          documents: documents,
          scale: 2,
          padding: const EdgeInsets.only(top: 12, bottom: 24),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('documentCollectionScroll')),
          findsOneWidget,
        );
        final next = find.byKey(const Key('loadMoreDocuments'));
        final collectionScroll = find
            .descendant(
              of: find.byKey(const Key('documentCollectionScroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        await revealWorkspaceContent(
          tester,
          next,
          scrollable: collectionScroll,
          maxAttempts: DocumentsCubit.pageSize * 4,
        );
        expect(find.byKey(const Key('documentCount')), findsOneWidget);
        expect(next.hitTestable(), findsOneWidget);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(documents.offsets.last, DocumentsCubit.pageSize);
        expect(documents.offsets.where((offset) => offset != 0), [
          DocumentsCubit.pageSize,
        ]);
        await revealWorkspaceContent(
          tester,
          find.text('Page 2 of 2'),
          scrollable: collectionScroll,
        );
        expect(find.text('Page 2 of 2'), findsOneWidget);
        final bottom = find.byKey(const Key('workspaceBottomNavigation'));
        expect(
          tester.getSize(bottom).height,
          lessThanOrEqualTo((320 - 12) * .4),
        );
        await navigateWorkspace(tester, 'manageLibraries');
        final accept = find.byKey(const Key('acceptInvitation'));
        await revealWorkspaceContent(
          tester,
          accept,
          scrollable: find
              .ancestor(of: accept, matching: find.byType(Scrollable))
              .first,
        );
        expect(accept.hitTestable(), findsOneWidget);
        await tester.tap(accept);
        await tester.pumpAndSettle();
        expect(
          find.text('Paste the complete invitation code.'),
          findsOneWidget,
        );
        if (admin) {
          await navigateWorkspace(
            tester,
            'manageSystemUsers',
            group: 'Admin settings',
          );
          expect(
            find.byWidgetPredicate(
              (widget) => widget is AppPage && widget.title == 'System users',
            ),
            findsOneWidget,
          );
        }
        await navigateWorkspace(tester, 'documentsNavigation');
        expect(
          find.byKey(const Key('documentCollectionScroll')),
          findsOneWidget,
        );
        expect(find.text('Page 2 of 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'limited account keeps Documents landing and settings without data access',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final original = testSession(role: AccountRole.viewer);
      final documents = FakeDocumentRepository();
      final session = AuthSession(
        token: original.token,
        expiresAt: original.expiresAt,
        identity: Identity(
          userId: 'limited',
          email: 'limited@example.test',
          accountId: 'limited-account',
          accountName: 'Limited account',
          role: AccountRole.viewer,
          mustChangePassword: false,
          permissions: [],
        ),
      );
      await mount(
        tester,
        session: session,
        identity: FakeIdentityRepository(),
        documents: documents,
      );
      expect(find.text('Library access is limited'), findsOneWidget);
      expect(find.byKey(const Key('documentsNavigation')), findsOneWidget);
      expect(find.byKey(const Key('newDocument')), findsNothing);
      expect(documents.offsets, isEmpty);
      await navigateWorkspace(tester, 'manageLibraries');
      expect(find.byKey(const Key('acceptInvitationCode')), findsOneWidget);
      await navigateWorkspace(tester, 'licensesNavigation');
      expect(find.byKey(const Key('licensesScreen')), findsOneWidget);
      await navigateWorkspace(tester, 'documentsNavigation');
      expect(find.text('Library access is limited'), findsOneWidget);
      expect(documents.offsets, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'initial-password gate has no workspace navigation or document load',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final documents = FakeDocumentRepository();
      await mount(
        tester,
        session: testSession(
          mustChangePassword: true,
          systemRole: SystemRole.admin,
        ),
        identity: FakeIdentityRepository(),
        documents: documents,
      );
      expect(find.text('Change initial password'), findsOneWidget);
      expect(find.byType(AppWorkspaceShell), findsNothing);
      expect(find.byKey(const Key('workspaceBottomNavigation')), findsNothing);
      expect(documents.offsets, isEmpty);
    },
  );

  testWidgets('document window blocks the mobile workspace until closed', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final documents = FakeDocumentRepository()
      ..records = [
        Document(
          id: 'one',
          title: 'Full screen document',
          description: '',
          createdAt: DateTime.utc(2026),
        ),
      ];
    await mount(
      tester,
      session: testSession(),
      identity: FakeIdentityRepository(),
      documents: documents,
    );
    await tester.tap(find.text('Full screen document'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('documentDetails')), findsOneWidget);
    expect(
      find.byKey(const Key('workspaceBottomNavigation')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(const Key('documentWindow')), findsOneWidget);
    await tester.tap(find.byKey(const Key('closeDocument')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workspaceBottomNavigation')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
