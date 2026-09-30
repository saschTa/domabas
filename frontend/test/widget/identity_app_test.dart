import "../support/fake_appearance_repository.dart";
import '../support/fake_realtime_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_activity_repository.dart';
import "../support/fake_processing_repository.dart";

import 'dart:async';

import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/domabas_app.dart';
import 'package:domabas/app/session_client.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/data/identity/datasources/identity_remote_data_source.dart';
import 'package:domabas/data/identity/repos/remote_identity_repository.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_document_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/workspace_navigation.dart';

Future<void> signIn(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('authEmail')),
    'person@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('authPassword')),
    'long password 2026',
  );
  await tester.ensureVisible(find.byKey(const Key('submitAuth')));
  await tester.tap(find.byKey(const Key('submitAuth')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'narrow viewer sees own account and has no create or member controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuthRepository()
        ..next = testSession(role: AccountRole.viewer);
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
            identity: FakeIdentityRepository(),
            close: () {},
          ),
        ),
      );
      await signIn(tester);
      expect(find.text('Account a'), findsOneWidget);
      await tester.tap(find.byKey(const Key('navigation-user-settings')));
      await tester.pumpAndSettle();
      expect(find.text('a@example.com'), findsOneWidget);
      expect(find.byKey(const Key('newDocument')), findsNothing);
      expect(find.byKey(const Key('manageMembers')), findsNothing);
      expect(find.byKey(const Key('changePassword')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'initial password is required, wrong current password retains session, success signs out',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuthRepository()
        ..next = testSession(mustChangePassword: true);
      final identity = FakeIdentityRepository()
        ..changeFailure = const IdentityFailure(
          IdentityFailureKind.invalidCredentials,
        );
      final documents = FakeDocumentRepository();
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
            documents: documents,
            identity: identity,
            close: () {},
          ),
        ),
      );
      await signIn(tester);
      expect(find.text('Change initial password'), findsOneWidget);
      expect(documents.offsets, isEmpty);
      expect(find.byKey(const Key('newDocument')), findsNothing);
      expect(find.byKey(const Key('manageMembers')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('currentPassword')),
        'old password 2026',
      );
      await tester.enterText(
        find.byKey(const Key('newPassword')),
        'new password 2026',
      );
      await tester.enterText(
        find.byKey(const Key('confirmPassword')),
        'new password 2026',
      );
      await tester.ensureVisible(find.byKey(const Key('savePassword')));
      await tester.tap(find.byKey(const Key('savePassword')));
      await tester.pumpAndSettle();
      expect(find.text('Your current password is incorrect.'), findsOneWidget);
      expect(find.byKey(const Key('authEmail')), findsNothing);
      identity.changeFailure = null;
      await tester.ensureVisible(find.byKey(const Key('savePassword')));
      await tester.tap(find.byKey(const Key('savePassword')));
      await tester.pumpAndSettle();
      expect(identity.passwordChanged, isTrue);
      expect(find.byKey(const Key('authEmail')), findsOneWidget);
      expect(find.byKey(const Key('currentPassword')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('owner issues a code once, edits claims and cannot edit owners', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    final identity = FakeIdentityRepository()
      ..members = [
        AccountMember(
          id: 'owner',
          email: 'owner@example.com',
          role: AccountRole.admin,
          enabled: true,
          mustChangePassword: false,
          isOwner: true,
        ),
        AccountMember(
          id: 'member',
          email: 'member@example.com',
          role: AccountRole.viewer,
          claims: const [IdentityPermission.createDocuments],
          enabled: true,
          mustChangePassword: false,
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
    await navigateWorkspace(tester, 'manageMembers');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit owner@example.com'), findsNothing);
    await tester.tap(find.byKey(const Key('inviteMember')));
    await tester.pumpAndSettle();
    final inheritedRead = tester.widget<CheckboxListTile>(
      find.byKey(const Key('claim-documents:read')),
    );
    expect(inheritedRead.value, isTrue);
    expect(inheritedRead.onChanged, isNull);
    expect(find.text('Library access'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('inviteEmail')),
      'invited@example.com',
    );
    await tester.ensureVisible(find.byKey(const Key('claim-documents:create')));
    await tester.tap(find.byKey(const Key('claim-documents:create')));
    await tester.tap(find.byKey(const Key('saveMember')));
    await tester.pumpAndSettle();
    expect(identity.invitations.single.claims, {
      IdentityPermission.createDocuments,
    });
    expect(identity.creations, 0);
    expect(find.byKey(const Key('invitationCode')), findsOneWidget);
    await tester.tap(find.byKey(const Key('closeInvitationCode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invitationCode')), findsNothing);
    await tester.tap(find.byTooltip('Edit member@example.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('memberRole')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('User').last);
    await tester.pumpAndSettle();
    final inheritedCreate = tester.widget<CheckboxListTile>(
      find.byKey(const Key('claim-documents:create')),
    );
    expect(inheritedCreate.value, isTrue);
    expect(inheritedCreate.onChanged, isNull);
    await tester.ensureVisible(find.byKey(const Key('memberEnabled')));
    await tester.tap(find.byKey(const Key('memberEnabled')));
    await tester.tap(find.byKey(const Key('saveMember')));
    await tester.pumpAndSettle();
    expect(identity.members.last.role, AccountRole.user);
    expect(identity.members.last.enabled, isFalse);
    expect(
      identity.members.last.claims,
      contains(IdentityPermission.createDocuments),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'library switch replaces the navigator and ignores an old session callback',
    (tester) async {
      final auth = FakeAuthRepository();
      final callbacks = <VoidCallback>[];
      final documentScopes = <FakeDocumentRepository>[];
      final first = auth.next;
      final target = AccountMembership(
        id: 'shared',
        name: 'Shared library',
        role: AccountRole.viewer,
        isOwner: false,
        claims: [],
        permissions: [IdentityPermission.readDocuments],
      );
      final repository = FakeIdentityRepository()
        ..accounts = [target]
        ..onSwitch = (id) async => AuthSession(
          token: 'new-token',
          expiresAt: first.expiresAt,
          identity: Identity(
            userId: first.identity.userId,
            email: first.identity.email,
            accountId: id,
            accountName: target.name,
            role: target.role,
            mustChangePassword: false,
            permissions: target.permissions,
          ),
        );
      var closed = 0;
      await tester.pumpWidget(
        DomabasApp(
          appearance: FakeAppearanceRepository(),
          auth: auth,
          authenticate: (_, expired) {
            callbacks.add(expired);
            final documents = FakeDocumentRepository();
            documentScopes.add(documents);
            return AuthenticatedDependencies(
              realtime: FakeRealtimeRepository(),
              email: FakeEmailRepository(),
              activity: FakeActivityRepository(),
              processing: FakeProcessingRepository(),
              externalLinks: FakeExternalLinkLauncher(),
              documents: documents,
              identity: repository,
              close: () => closed++,
            );
          },
        ),
      );
      await signIn(tester);
      await tester.tap(find.byKey(const Key('librarySwitcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('switch-shared')));
      await tester.pumpAndSettle();
      expect(find.text('Your libraries'), findsNothing);
      expect(find.text('Shared library'), findsOneWidget);
      expect(find.byKey(const Key('newDocument')), findsNothing);
      expect(closed, 1);
      expect(documentScopes.first.cancelled, isTrue);
      expect(documentScopes.last.cancelled, isFalse);
      callbacks.first();
      await tester.pumpAndSettle();
      expect(find.text('Shared library'), findsOneWidget);
      expect(find.byKey(const Key('authEmail')), findsNothing);
      expect(documentScopes.last.cancelled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system roles are managed separately and explain last-admin conflicts',
    (tester) async {
      final auth = FakeAuthRepository()
        ..next = testSession(systemRole: SystemRole.admin);
      final repository = FakeIdentityRepository()
        ..users = [
          SystemUser(
            id: 'user-a',
            email: 'a@example.com',
            role: SystemRole.admin,
            createdAt: DateTime.utc(2026),
          ),
          SystemUser(
            id: 'other',
            email: 'other@example.com',
            role: SystemRole.user,
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
            identity: repository,
            close: () {},
          ),
        ),
      );
      await signIn(tester);
      await navigateWorkspace(
        tester,
        'manageSystemUsers',
        group: 'Admin settings',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('system-role-user-a')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('The last administrator.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('system-role-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('system-role-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmSystemRole')));
      await tester.pumpAndSettle();
      expect(repository.users.last.role, SystemRole.admin);
      repository.systemFailure = const IdentityFailure(
        IdentityFailureKind.conflict,
      );
      await tester.ensureVisible(find.byKey(const Key('system-role-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('system-role-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmSystemRole')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('At least one system administrator'),
        findsOneWidget,
      );
      expect(repository.users.last.role, SystemRole.admin);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'session replacement removes open detail route and ignores its late result and old 401',
    (tester) async {
      final auth = FakeAuthRepository();
      final oldDocuments = _PendingDetailRepository();
      final callbacks = <VoidCallback>[];
      var closed = 0;
      await tester.pumpWidget(
        DomabasApp(
          appearance: FakeAppearanceRepository(),
          auth: auth,
          authenticate: (session, expired) {
            callbacks.add(expired);
            return AuthenticatedDependencies(
              realtime: FakeRealtimeRepository(),
              email: FakeEmailRepository(),
              activity: FakeActivityRepository(),
              processing: FakeProcessingRepository(),
              externalLinks: FakeExternalLinkLauncher(),
              documents: session.identity.accountId == 'account-a'
                  ? oldDocuments
                  : FakeDocumentRepository(),
              identity: FakeIdentityRepository(),
              close: () => closed++,
            );
          },
        ),
      );
      await signIn(tester);
      await tester.tap(find.text('Private A document'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('documentDetails')), findsOneWidget);
      callbacks.first();
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(find.byKey(const Key('documentDetails')), findsNothing);
      auth.next = testSession(suffix: 'b');
      await signIn(tester);
      oldDocuments.detail.complete(oldDocuments.document);
      callbacks.first();
      await tester.pumpAndSettle();
      expect(find.text('Account b'), findsOneWidget);
      expect(find.text('Private A document'), findsNothing);
      expect(find.byKey(const Key('documentDetails')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logout retains its generated API transport until DELETE completes while protected UI clears',
    (tester) async {
      final auth = FakeAuthRepository();
      final transport = _PendingLogoutClient();
      final documents = FakeDocumentRepository();
      late SessionClient client;
      await tester.pumpWidget(
        DomabasApp(
          appearance: FakeAppearanceRepository(),
          auth: auth,
          authenticate: (session, expired) {
            client = SessionClient(
              transport,
              token: session.token,
              onUnauthorized: expired,
            );
            final generated = api.ApiClient(basePath: 'http://example.test');
            generated.client.close();
            generated.client = client;
            return AuthenticatedDependencies(
              realtime: FakeRealtimeRepository(),
              email: FakeEmailRepository(),
              activity: FakeActivityRepository(),
              processing: FakeProcessingRepository(),
              externalLinks: FakeExternalLinkLauncher(),
              documents: documents,
              identity: RemoteIdentityRepository(
                IdentityRemoteDataSource(api.IdentityApi(generated)),
              ),
              close: client.close,
            );
          },
        ),
      );
      await signIn(tester);
      await revealWorkspaceAction(tester, 'logout');
      await tester.tap(find.byKey(const Key('logout')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('authEmail')), findsOneWidget);
      expect(find.text('Account a'), findsNothing);
      expect(documents.cancelled, isTrue);
      expect(transport.closed, isFalse);
      expect(transport.request?.method, 'DELETE');
      expect(transport.request?.url.path, '/api/v1/auth/session');
      expect(
        transport.request?.headers['Authorization'],
        'Bearer ${auth.next.token}',
      );
      transport.response.complete(
        http.StreamedResponse(const Stream.empty(), 204),
      );
      await tester.pumpAndSettle();
      expect(transport.closed, isTrue);
      expect(find.text('You have signed out.'), findsOneWidget);
    },
  );
}

final class _PendingDetailRepository extends FakeDocumentRepository {
  final detail = Completer<Document>();
  final document = Document(
    id: 'private-a',
    title: 'Private A document',
    description: 'Private',
    createdAt: DateTime.utc(2026),
  );

  @override
  Future<DocumentPage> list({
    int limit = 50,
    int offset = 0,
    String? cursor,
    Future<void>? cancel,
  }) async => DocumentPage(items: [document], total: 1);

  @override
  Future<Document> create(DocumentDraft draft) => throw UnimplementedError();

  @override
  Future<Document> getById(String id, {Future<void>? cancel}) => detail.future;
}

final class _PendingLogoutClient extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  http.BaseRequest? request;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    this.request = request;
    return response.future;
  }

  @override
  void close() => closed = true;
}
