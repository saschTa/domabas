import "../support/fake_appearance_repository.dart";
import '../support/fake_realtime_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_activity_repository.dart';
import "../support/fake_processing_repository.dart";

import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/domabas_app.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:flutter/material.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/navigation_fonts.dart';
import '../support/workspace_navigation.dart';
import 'identity_app_test.dart' show signIn;

void main() {
  setUpAll(loadNavigationFonts);
  for (final (width, scale) in [
    (320.0, 1.0),
    (320.0, 2.0),
    (390.0, 1.0),
    (390.0, 2.0),
    (900.0, 1.0),
    (900.0, 2.0),
    (1440.0, 1.0),
    (1440.0, 2.0),
  ]) {
    testWidgets(
      'settings and role dialog stay usable at width $width and text scale $scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final auth = FakeAuthRepository()
          ..next = testSession(systemRole: SystemRole.admin);
        final identity = FakeIdentityRepository()
          ..accounts = [
            AccountMembership(
              id: 'account-a',
              name: 'A library with a deliberately long name for responsive layouts',
              role: AccountRole.admin,
              isOwner: true,
              claims: [],
              permissions: [IdentityPermission.readDocuments],
            ),
          ]
          ..users = [
            SystemUser(
              id: 'user-a',
              email: 'administrator-with-a-long-address@example.test',
              role: SystemRole.admin,
              createdAt: DateTime.utc(2026),
            ),
          ];
        await tester.pumpWidget(
          DomabasApp(
            appearance: FakeAppearanceRepository(),
            auth: auth,
            authenticate: (_, _) => AuthenticatedDependencies(
              realtime: FakeRealtimeRepository(),
              email: FakeEmailRepository(),
              activity: FakeActivityRepository(),
              processing: FakeProcessingRepository(),
              externalLinks: FakeExternalLinkLauncher(),
              documents: FakeDocumentRepository(),
              identity: identity,
              close: () {},
            ),
          ),
        );
        await signIn(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Your library'), findsNothing);
        expect(
          find.text('A clear home for the details that matter.'),
          findsNothing,
        );
        Rect headerRect() {
          final mobile = find.byType(GlacierMobileHeader);
          final viewport = find.ancestor(
            of: mobile,
            matching: find.byType(SingleChildScrollView),
          );
          return tester.getRect(
            mobile.evaluate().isNotEmpty
                ? viewport.evaluate().isNotEmpty
                      ? viewport.first
                      : mobile
                : find.byType(GlacierToolbar).first,
          );
        }

        final header = headerRect();
        expect(header.height, lessThanOrEqualTo(256));
        final navigation = find.byKey(const Key('workspaceBottomNavigation'));
        final bodyBottom = navigation.evaluate().isEmpty
            ? 1000.0
            : tester.getRect(navigation).top;
        expect(bodyBottom - header.bottom, greaterThanOrEqualTo(48));
        expect(
          find.byKey(
            Key(
              width >= 800 && width < 1050
                  ? 'workspaceAccount'
                  : 'librarySwitcher',
            ),
          ),
          findsOneWidget,
        );
        await revealWorkspaceAction(tester, 'newDocument');
        expect(find.byKey(const Key('newDocument')), findsOneWidget);
        await tester.tap(find.byKey(const Key('newDocument')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('documentTitle')), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await navigateWorkspace(tester, 'manageLibraries');
        if (width < 800) {
          expect(headerRect().height, lessThanOrEqualTo(256));
          expect(
            tester
                .widget<GlacierMobileHeader>(find.byType(GlacierMobileHeader))
                .subtitle,
            'Account a',
          );
        } else {
          expect(
            tester
                .widget<GlacierWorkspace>(find.byType(GlacierWorkspace))
                .libraryLabel,
            'Account a',
          );
        }
        expect(find.byKey(const Key('newDocument')), findsNothing);
        expect(
          find.byKey(
            Key(
              width >= 800 && width < 1050
                  ? 'workspaceAccount'
                  : 'librarySwitcher',
            ),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('acceptInvitationCode')), findsOneWidget);
        expect(find.text('Open library'), findsNothing);
        expect(tester.takeException(), isNull);
        await navigateWorkspace(tester, 'manageMembers');
        await tester.ensureVisible(find.byKey(const Key('inviteMember')));
        await tester.tap(find.byKey(const Key('inviteMember')));
        await tester.pumpAndSettle();
        final read = tester.widget<GlacierChoice>(
          find.byKey(const Key('claim-documents:read')),
        );
        expect(read.selected, isTrue);
        expect(read.onChanged, isNull);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await navigateWorkspace(tester, 'manageInvitations');
        expect(find.byType(TabBarView), findsNothing);
        expect(tester.takeException(), isNull);
        await navigateWorkspace(tester, 'changePassword');
        expect(find.byKey(const Key('currentPassword')), findsOneWidget);
        if (width < 600) {
          final field = find.byKey(const Key('currentPassword'));
          await tester.enterText(field, 'retained draft');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          final formState = tester.state(field);
          final scroll = find.ancestor(
            of: field,
            matching: find.byType(SingleChildScrollView),
          );
          ScrollPosition currentPosition() => tester
              .state<ScrollableState>(
                find
                    .descendant(of: scroll, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          final position = currentPosition();
          position.jumpTo(40);
          await tester.pumpAndSettle();
          final offset = position.pixels;
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('workspaceBottomNavigation')),
            findsNothing,
          );
          expect(tester.state(field), same(formState));
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          expect(tester.state(field), same(formState));
          expect(currentPosition().pixels, offset);
          expect(
            tester.widget<TextFormField>(field).controller!.text,
            'retained draft',
          );
          currentPosition().jumpTo(currentPosition().maxScrollExtent);
          await tester.pumpAndSettle();
          final save = find.byKey(const Key('savePassword'));
          expect(
            tester.getRect(save).bottom,
            lessThan(
              tester
                  .getRect(find.byKey(const Key('workspaceBottomNavigation')))
                  .top,
            ),
          );
          expect(save.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await navigateWorkspace(
          tester,
          'manageSystemUsers',
          group: 'Admin settings',
        );
        final button = tester.widget<GlacierButton>(
          find.byKey(const Key('system-role-user-a')),
        );
        expect(button.onPressed, isNull);
        expect(tester.takeException(), isNull);
        var librarySwitcher = find.byKey(const Key('librarySwitcher'));
        if (width >= 800 && width < 1050) {
          await tester.tap(find.byKey(const Key('workspaceAccount')));
          await tester.pumpAndSettle();
          librarySwitcher = find.descendant(
            of: find.byType(Dialog),
            matching: librarySwitcher,
          );
        }
        expect(librarySwitcher.hitTestable(), findsOneWidget);
        await tester.tap(librarySwitcher);
        await tester.pumpAndSettle();
        expect(find.text('Switch library'), findsOneWidget);
        expect(find.byKey(const Key('switch-account-a')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
