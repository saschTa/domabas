import 'dart:async';

import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas/presentation/identity/cubits/libraries_cubit.dart';
import 'package:domabas/presentation/identity/cubits/account_cubit.dart';
import 'package:domabas/presentation/identity/cubits/session_cubit.dart';
import 'package:domabas/presentation/identity/cubits/system_users_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_identity_repository.dart';

AuthSession switched(
  AuthSession previous, {
  DateTime? expiry,
  String id = 'shared',
}) => AuthSession(
  token: 'replacement',
  expiresAt: expiry ?? previous.expiresAt,
  identity: Identity(
    userId: previous.identity.userId,
    email: previous.identity.email,
    accountId: id,
    accountName: 'Shared library',
    role: AccountRole.viewer,
    mustChangePassword: false,
    permissions: [IdentityPermission.readDocuments, 'documents:future'],
  ),
);

void main() {
  test('pending list responses gate invitation mutations until a fresh refresh can run', () async {
    final identity = testSession().identity;
    final repository = FakeIdentityRepository();
    final pendingAccounts = Completer<AccountPage>();
    repository.onAccounts = () => pendingAccounts.future;
    final libraries = LibrariesCubit(
      repository,
      identity: identity,
      onSwitch: (_) async => null,
    );
    final loadingAccounts = libraries.load();
    expect(await libraries.accept('code'), isFalse);
    pendingAccounts.complete(AccountPage(items: [], total: 0));
    await loadingAccounts;
    repository.onAccounts = null;
    final shared = AccountMembership(
      id: 'shared',
      name: 'Shared',
      role: AccountRole.viewer,
      isOwner: false,
      claims: [],
      permissions: [IdentityPermission.readDocuments],
    );
    repository.onAccept = (_) async {
      repository.accounts = [shared];
      return shared;
    };
    expect(await libraries.accept('code'), isTrue);
    expect(libraries.accounts.single.id, 'shared');
    await libraries.close();

    final pendingInvitations = Completer<InvitationPage>();
    repository.onInvitations = () => pendingInvitations.future;
    final account = AccountCubit(
      repository,
      identity: identity,
      onSessionEnded: (_) {},
    );
    final loadingInvitations = account.loadInvitations();
    expect(
      await account.invite('new@example.com', AccountRole.viewer, {}),
      isNull,
    );
    expect(repository.invitations, isEmpty);
    pendingInvitations.complete(InvitationPage(items: [], total: 0));
    await loadingInvitations;
    repository.onInvitations = null;
    expect(
      await account.invite('new@example.com', AccountRole.viewer, {}),
      isNotNull,
    );
    expect(account.invitations.single.email, 'new@example.com');
    await account.close();
  });

  test('switch installs a fresh scope without extending expiry and failures keep the old scope', () async {
    final auth = FakeAuthRepository();
    final sessions = SessionCubit(auth);
    addTearDown(sessions.close);
    await sessions.authenticate(email: 'a@example.com', password: 'password');
    final original = sessions.session!;
    final repository = FakeIdentityRepository()
      ..onSwitch = (_) async =>
          throw const IdentityFailure(IdentityFailureKind.notFound);
    expect(await sessions.switchAccount(repository, 'shared'), isFalse);
    expect(sessions.session, same(original));
    expect(sessions.error, isNotNull);
    final replacement = switched(original);
    repository.onSwitch = (_) async => replacement;
    expect(await sessions.switchAccount(repository, 'shared'), isTrue);
    expect(sessions.session, same(replacement));
    expect(sessions.session!.expiresAt, original.expiresAt);
    sessions.endSession(original, 'late old session failure');
    expect(sessions.session, same(replacement));
    expect(replacement.identity.allows('documents:future'), isTrue);
    expect(
      () => replacement.identity.permissions.clear(),
      throwsUnsupportedError,
    );
  });

  test('logout during switching prevents a late replacement from restoring identity', () async {
    final auth = FakeAuthRepository();
    final sessions = SessionCubit(auth);
    addTearDown(sessions.close);
    await sessions.authenticate(email: 'a@example.com', password: 'password');
    final original = sessions.session!;
    final pending = Completer<AuthSession>();
    final repository = FakeIdentityRepository()
      ..onSwitch = (_) => pending.future;
    final request = sessions.switchAccount(repository, 'shared');
    await sessions.logout(repository);
    pending.complete(switched(original));
    expect(await request, isFalse);
    expect(sessions.session, isNull);
    expect(sessions.busy, isFalse);
  });

  test('switch responses cannot extend authority lifetime or select a different namespace', () async {
    for (final wrongAccount in [false, true]) {
      final auth = FakeAuthRepository();
      final sessions = SessionCubit(auth);
      await sessions.authenticate(email: 'a@example.com', password: 'password');
      final previous = sessions.session!;
      final repository = FakeIdentityRepository()
        ..onSwitch = (_) async => switched(
          previous,
          expiry: wrongAccount
              ? previous.expiresAt
              : previous.expiresAt!.add(const Duration(seconds: 1)),
          id: wrongAccount ? 'foreign' : 'shared',
        );
      expect(await sessions.switchAccount(repository, 'shared'), isFalse);
      expect(sessions.session, isNull);
      await sessions.close();
    }
  });

  test('acceptance adds a namespace without switching and disposed responses are ignored', () async {
    final identity = testSession().identity;
    final shared = AccountMembership(
      id: 'shared',
      name: 'Shared',
      role: AccountRole.viewer,
      isOwner: false,
      claims: [IdentityPermission.createDocuments],
      permissions: [
        IdentityPermission.readDocuments,
        IdentityPermission.createDocuments,
      ],
    );
    final repository = FakeIdentityRepository();
    repository.onAccept = (_) async {
      repository.accounts = [shared];
      return shared;
    };
    var switches = 0;
    final model = LibrariesCubit(
      repository,
      identity: identity,
      onSwitch: (_) async {
        switches++;
        return null;
      },
    );
    expect(await model.accept('code'), isTrue);
    expect(model.accounts.single, same(shared));
    expect(model.identity.accountId, identity.accountId);
    expect(switches, 0);
    expect(() => shared.claims.clear(), throwsUnsupportedError);
    final pending = Completer<AccountMembership>();
    repository.onAccept = (_) => pending.future;
    final future = model.accept('another');
    await model.close();
    pending.complete(shared);
    expect(await future, isFalse);
  });

  test('self system-role change ends the current session without refreshing its revoked credentials', () async {
    final identity = testSession(systemRole: SystemRole.admin).identity;
    final repository = FakeIdentityRepository()
      ..users = [
        SystemUser(
          id: identity.userId,
          email: identity.email,
          role: SystemRole.admin,
          createdAt: DateTime.utc(2026),
        ),
        SystemUser(
          id: 'another-admin',
          email: 'another@example.com',
          role: SystemRole.admin,
          createdAt: DateTime.utc(2026),
        ),
      ];
    var reads = 0;
    repository.onSystemUsers = (_, _) async {
      reads++;
      return SystemUserPage(items: repository.users, total: 2, adminCount: 2);
    };
    String? ended;
    final model = SystemUsersCubit(
      repository,
      identity: identity,
      onSessionEnded: (message) => ended = message,
    );
    addTearDown(model.close);
    await model.load();
    await model.update(model.users.first, SystemRole.user);
    expect(ended, contains('system role changed'));
    expect(repository.users.first.role, SystemRole.user);
    expect(reads, 1);
    expect(model.adminCount, isNull);
  });

  test('role claims come from the scoped catalog and explicit grants keep their provenance', () async {
    final sourceRoles = ['viewer', 'new-role'];
    final claim = IdentityClaim(
      id: 'documents:future',
      label: 'Future document action',
      scope: IdentityClaimScope.namespace,
      roles: sourceRoles,
    );
    sourceRoles.clear();
    expect(claim.roles, {'viewer', 'new-role'});
    expect(() => claim.roles.clear(), throwsUnsupportedError);
    final repository = FakeIdentityRepository()..catalog.add(claim);
    final model = AccountCubit(
      repository,
      identity: testSession(extraPermissions: ['documents:future']).identity,
      onSessionEnded: (_) {},
    );
    addTearDown(model.close);
    expect(model.canAssignRole(AccountRole.viewer), isFalse);
    await model.load();
    expect(model.roleClaims(AccountRole.viewer), {
      IdentityPermission.readDocuments,
      'documents:future',
    });
    expect(
      model.roleClaims(AccountRole.admin),
      isNot(contains(IdentityPermission.manageSystemUsers)),
    );
    final additional = {IdentityPermission.createDocuments};
    expect(model.effectiveClaims(AccountRole.user, additional), {
      IdentityPermission.readDocuments,
      IdentityPermission.createDocuments,
    });
    expect(model.effectiveClaims(AccountRole.viewer, additional), {
      IdentityPermission.readDocuments,
      IdentityPermission.createDocuments,
      'documents:future',
    });
    expect(additional, {IdentityPermission.createDocuments});
    expect(model.canAssignRole(AccountRole.viewer), isTrue);
    await model.invite('new@example.com', AccountRole.viewer, additional);
    expect(repository.invitations.single.claims, {
      IdentityPermission.createDocuments,
    });

    final delegate = AccountCubit(
      repository,
      identity: testSession(
        role: AccountRole.viewer,
        extraPermissions: [IdentityPermission.manageUsers, 'documents:future'],
      ).identity,
      onSessionEnded: (_) {},
    );
    addTearDown(delegate.close);
    await delegate.load();
    expect(delegate.canAssignRole(AccountRole.viewer), isTrue);
    expect(delegate.canAssignRole(AccountRole.user), isFalse);
    expect(delegate.canAssignRole(AccountRole.admin), isFalse);
  });

  test('unknown count, pending loads, unchanged roles and final admin cannot submit writes', () async {
    final identity = testSession(systemRole: SystemRole.admin).identity;
    final admin = SystemUser(
      id: identity.userId,
      email: identity.email,
      role: SystemRole.admin,
      createdAt: DateTime.utc(2026),
    );
    final repository = FakeIdentityRepository()..users = [admin];
    final model = SystemUsersCubit(
      repository,
      identity: identity,
      onSessionEnded: (_) {},
    );
    addTearDown(model.close);
    await model.update(admin, SystemRole.user);
    expect(repository.systemUpdates, 0);
    final pending = Completer<SystemUserPage>();
    repository.onSystemUsers = (_, _) => pending.future;
    final loading = model.load();
    await model.update(admin, SystemRole.user);
    expect(repository.systemUpdates, 0);
    pending.complete(SystemUserPage(items: [admin], total: 1, adminCount: 1));
    await loading;
    expect(model.isLastAdministrator(admin), isTrue);
    expect(model.canChangeRole(admin, SystemRole.user), isFalse);
    await model.update(admin, SystemRole.user);
    await model.update(admin, SystemRole.admin);
    expect(repository.systemUpdates, 0);
  });

  test('global count permits off-page admin demotion and refreshes after mutations', () async {
    final identity = testSession(systemRole: SystemRole.admin).identity;
    final admin = SystemUser(
      id: 'other-admin',
      email: 'other@example.com',
      role: SystemRole.admin,
      createdAt: DateTime.utc(2026),
    );
    final repository = FakeIdentityRepository()..users = [admin];
    var reads = 0;
    repository.onSystemUsers = (_, _) async {
      reads++;
      return SystemUserPage(
        items: repository.users,
        total: 60,
        adminCount: reads == 1 ? 2 : 1,
      );
    };
    final model = SystemUsersCubit(
      repository,
      identity: identity,
      onSessionEnded: (_) => fail('foreign change ends session'),
    );
    addTearDown(model.close);
    await model.load();
    expect(model.adminCount, 2);
    expect(model.users, hasLength(1));
    expect(model.canChangeRole(admin, SystemRole.user), isTrue);
    await model.update(admin, SystemRole.user);
    expect(repository.systemUpdates, 1);
    expect(model.adminCount, 1);
    expect(model.users.single.role, SystemRole.user);
    expect(reads, 2);
  });

  test('a concurrent final-admin conflict refreshes count without clearing its explanation', () async {
    final identity = testSession(systemRole: SystemRole.admin).identity;
    final admin = SystemUser(
      id: 'other-admin',
      email: 'other@example.com',
      role: SystemRole.admin,
      createdAt: DateTime.utc(2026),
    );
    final repository = FakeIdentityRepository()
      ..users = [admin]
      ..systemFailure = const IdentityFailure(IdentityFailureKind.conflict);
    var reads = 0;
    repository.onSystemUsers = (_, _) async => SystemUserPage(
      items: [admin],
      total: 2,
      adminCount: ++reads == 1 ? 2 : 1,
    );
    final model = SystemUsersCubit(
      repository,
      identity: identity,
      onSessionEnded: (_) => fail('failed change ends session'),
    );
    addTearDown(model.close);
    await model.load();
    await model.update(admin, SystemRole.user);
    expect(model.adminCount, 1);
    expect(model.isLastAdministrator(admin), isTrue);
    expect(model.error, contains('At least one system administrator'));
    expect(model.canChangeRole(admin, SystemRole.user), isFalse);
    expect(reads, 2);
  });

  test('disposal ignores late counts from a pending refresh', () async {
    final identity = testSession(systemRole: SystemRole.admin).identity;
    final repository = FakeIdentityRepository();
    final model = SystemUsersCubit(
      repository,
      identity: identity,
      onSessionEnded: (_) {},
    );
    await model.load();
    final pending = Completer<SystemUserPage>();
    repository.onSystemUsers = (_, _) => pending.future;
    final loading = model.load();
    expect(model.adminCount, 0);
    await model.close();
    pending.complete(SystemUserPage(items: [], total: 3, adminCount: 2));
    await loading;
    expect(model.adminCount, 0);
  });
}
