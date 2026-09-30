import 'dart:async';

import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas/domain/identity/models/personal_activity.dart';
import 'package:domabas/presentation/identity/cubits/account_cubit.dart';
import 'package:domabas/presentation/identity/cubits/libraries_cubit.dart';
import 'package:domabas/presentation/identity/cubits/personal_activity_cubit.dart';
import 'package:domabas/presentation/identity/cubits/system_users_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_identity_repository.dart';

final _identity = testSession(systemRole: SystemRole.admin).identity;

AccountMember _member({bool owner = false}) => AccountMember(
  id: 'other',
  email: 'other@example.com',
  role: AccountRole.viewer,
  enabled: true,
  mustChangePassword: false,
  isOwner: owner,
);

AccountMembership _library() => AccountMembership(
  id: 'shared',
  name: 'Shared',
  role: AccountRole.viewer,
  isOwner: false,
  claims: [],
  permissions: [IdentityPermission.readDocuments],
);

SystemUser _user({SystemRole role = SystemRole.admin}) => SystemUser(
  id: 'other',
  email: 'other@example.com',
  role: role,
  createdAt: DateTime.utc(2026),
);

Invitation _invitation(InvitationStatus status) => Invitation(
  id: 'invitation',
  email: 'other@example.com',
  role: AccountRole.viewer,
  claims: [],
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2027),
  status: status,
);

class _ActivityRepository extends FakeActivityRepository {
  int reads = 0;
  Completer<PersonalActivity>? pending;
  Future<void>? cancellation;

  @override
  Future<PersonalActivity> getActivity({
    String? activeCursor,
    String? finishedCursor,
    Future<void>? cancel,
  }) async {
    reads++;
    cancellation = cancel;
    return pending == null ? activity : await pending!.future;
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'empty identity snapshots refresh silently and explicit reads show loading',
    () async {
      final repository = FakeIdentityRepository();
      final account = AccountCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      final libraries = LibrariesCubit(
        repository,
        identity: _identity,
        onSwitch: (_) async => null,
      );
      final users = SystemUsersCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      addTearDown(account.close);
      addTearDown(libraries.close);
      addTearDown(users.close);
      await account.load();
      await account.loadInvitations();
      await libraries.load();
      await users.load();

      for (final preserve in [true, false]) {
        final members = Completer<MemberPage>();
        final invitations = Completer<InvitationPage>();
        final accounts = Completer<AccountPage>();
        final system = Completer<SystemUserPage>();
        repository.onList = () => members.future;
        repository.onInvitations = () => invitations.future;
        repository.onAccounts = () => accounts.future;
        repository.onSystemUsers = (_, _) => system.future;
        final reads = [
          account.load(preserve: preserve),
          account.loadInvitations(preserve: preserve),
          libraries.load(preserve: preserve),
          users.load(preserve: preserve),
        ];
        expect(account.loading, !preserve);
        expect(account.loadingInvitations, !preserve);
        expect(libraries.loading, !preserve);
        expect(users.loading, !preserve);
        expect(users.adminCount, 0);
        final explicit = preserve
            ? [
                account.load(),
                account.loadInvitations(),
                libraries.load(),
                users.load(),
              ]
            : <Future<void>>[];
        expect(account.loading, isTrue);
        expect(account.loadingInvitations, isTrue);
        expect(libraries.loading, isTrue);
        expect(users.loading, isTrue);
        members.complete(MemberPage(items: [], total: 0));
        invitations.complete(InvitationPage(items: [], total: 0));
        accounts.complete(AccountPage(items: [], total: 0));
        system.complete(SystemUserPage(items: [], total: 0, adminCount: 0));
        await Future.wait([...reads, ...explicit]);
      }
    },
  );

  test(
    'member save waits for refresh then preserves its confirmed update',
    () async {
      final member = _member();
      final repository = FakeIdentityRepository()..members = [member];
      final account = AccountCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      addTearDown(account.close);
      await account.load();
      final pending = Completer<MemberPage>();
      repository.onList = () => pending.future;
      final reading = account.load(preserve: true);
      expect(account.canAssignRole(AccountRole.user), isTrue);
      final updating = account.updateMember(member, AccountRole.user, true);
      await _flush();
      expect(repository.members.single.role, AccountRole.viewer);
      pending.complete(MemberPage(items: [member], total: 1));
      await reading;
      expect(await updating, isTrue);
      expect(account.members.single.role, AccountRole.user);
    },
  );

  for (final changed in ['owner', 'removed', 'permission', 'failed']) {
    test('member save revalidates $changed after refresh', () async {
      final member = _member();
      final repository = FakeIdentityRepository()..members = [member];
      final account = AccountCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      addTearDown(account.close);
      await account.load();
      final pending = Completer<MemberPage>();
      repository.onList = () => pending.future;
      final reading = account.load(preserve: true);
      final updating = account.updateMember(member, AccountRole.user, true);
      if (changed == 'permission') {
        account.updateDisplay(testSession(role: AccountRole.viewer).identity);
      }
      if (changed == 'failed') {
        await _flush();
        pending.completeError(
          const IdentityFailure(IdentityFailureKind.unavailable),
        );
      } else {
        final items = changed == 'removed'
            ? <AccountMember>[]
            : [_member(owner: changed == 'owner')];
        pending.complete(MemberPage(items: items, total: items.length));
      }
      await reading;
      expect(await updating, isFalse);
      expect(repository.members.single.role, AccountRole.viewer);
    });
  }

  test(
    'inviting waits for the empty background snapshot and publishes new row',
    () async {
      final repository = FakeIdentityRepository();
      final account = AccountCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      addTearDown(account.close);
      await account.load();
      await account.loadInvitations();
      final pending = Completer<InvitationPage>();
      repository.onInvitations = () => pending.future;
      final reading = account.loadInvitations(preserve: true);
      final inviting = account.invite(
        'new@example.com',
        AccountRole.viewer,
        {},
      );
      await _flush();
      expect(repository.invitations, isEmpty);
      repository.onInvitations = null;
      pending.complete(InvitationPage(items: [], total: 0));
      await reading;
      expect(await inviting, isNotNull);
      expect(account.invitations.single.email, 'new@example.com');
    },
  );

  test(
    'revocation rechecks invitation status after background refresh',
    () async {
      final invitation = _invitation(InvitationStatus.pending);
      final repository = FakeIdentityRepository()..invitations = [invitation];
      final account = AccountCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      addTearDown(account.close);
      await account.loadInvitations();
      final pending = Completer<InvitationPage>();
      repository.onInvitations = () => pending.future;
      final reading = account.loadInvitations(preserve: true);
      final revoking = account.revoke(invitation);
      pending.complete(
        InvitationPage(
          items: [_invitation(InvitationStatus.accepted)],
          total: 1,
        ),
      );
      await reading;
      expect(await revoking, isFalse);
      expect(repository.invitations.single.status, InvitationStatus.pending);
    },
  );

  test(
    'accepting an invitation waits for refresh without losing the new library',
    () async {
      final shared = _library();
      final repository = FakeIdentityRepository();
      repository.onAccept = (_) async {
        repository.accounts = [shared];
        return shared;
      };
      final libraries = LibrariesCubit(
        repository,
        identity: _identity,
        onSwitch: (_) async => null,
      );
      addTearDown(libraries.close);
      await libraries.load();
      final pending = Completer<AccountPage>();
      repository.onAccounts = () => pending.future;
      final reading = libraries.load(preserve: true);
      final accepting = libraries.accept('code');
      await _flush();
      expect(repository.accounts, isEmpty);
      repository.onAccounts = null;
      pending.complete(AccountPage(items: [], total: 0));
      await reading;
      expect(await accepting, isTrue);
      expect(libraries.accounts.single, same(shared));
    },
  );

  for (final result in ['retained', 'removed', 'failed']) {
    test('switch waits for refresh and rechecks $result library', () async {
      final shared = _library();
      final repository = FakeIdentityRepository()..accounts = [shared];
      var switches = 0;
      final libraries = LibrariesCubit(
        repository,
        identity: _identity,
        onSwitch: (_) async {
          switches++;
          return null;
        },
      );
      addTearDown(libraries.close);
      await libraries.load();
      final pending = Completer<AccountPage>();
      repository.onAccounts = () => pending.future;
      final reading = libraries.load(preserve: true);
      final switching = libraries.switchTo(shared);
      await _flush();
      expect(switches, 0);
      if (result == 'failed') {
        pending.completeError(
          const IdentityFailure(IdentityFailureKind.unavailable),
        );
      } else {
        final items = result == 'retained' ? [shared] : <AccountMembership>[];
        pending.complete(AccountPage(items: items, total: items.length));
      }
      await reading;
      await switching;
      expect(switches, result == 'retained' ? 1 : 0);
    });
  }

  for (final count in [1, 2]) {
    test(
      'system role action waits and uses refreshed administrator count $count',
      () async {
        final admin = _user();
        final repository = FakeIdentityRepository()..users = [admin];
        repository.onSystemUsers = (_, _) async =>
            SystemUserPage(items: repository.users, total: 1, adminCount: 2);
        final users = SystemUsersCubit(
          repository,
          identity: _identity,
          onSessionEnded: (_) {},
        );
        addTearDown(users.close);
        await users.load();
        final pending = Completer<SystemUserPage>();
        repository.onSystemUsers = (_, _) => pending.future;
        final reading = users.load(preserve: true);
        expect(users.loading, isFalse);
        expect(users.adminCount, 2);
        expect(users.canChangeRole(admin, SystemRole.user), isTrue);
        final updating = users.update(admin, SystemRole.user);
        await _flush();
        expect(repository.systemUpdates, 0);
        repository.onSystemUsers = (_, _) async =>
            SystemUserPage(items: repository.users, total: 1, adminCount: 1);
        pending.complete(
          SystemUserPage(items: [admin], total: 1, adminCount: count),
        );
        await reading;
        await updating;
        expect(repository.systemUpdates, count == 1 ? 0 : 1);
        expect(users.adminCount, 1);
      },
    );
  }

  test(
    'failed system refresh keeps last-admin evidence and blocks role writes',
    () async {
      final admin = _user();
      final repository = FakeIdentityRepository()..users = [admin];
      final users = SystemUsersCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      addTearDown(users.close);
      await users.load();
      repository.onSystemUsers = (_, _) async =>
          throw const IdentityFailure(IdentityFailureKind.unavailable);
      await users.load(preserve: true);
      expect(users.adminCount, 1);
      expect(users.isLastAdministrator(admin), isTrue);
      final error = users.error;
      expect(error, isNotNull);
      final pending = Completer<SystemUserPage>();
      repository.onSystemUsers = (_, _) => pending.future;
      final reading = users.load(preserve: true);
      expect(users.error, error);
      expect(users.adminCount, 1);
      expect(users.canChangeRole(admin, SystemRole.user), isFalse);
      pending.complete(SystemUserPage(items: [admin], total: 1, adminCount: 2));
      await reading;
      expect(users.error, isNull);
      expect(users.canChangeRole(admin, SystemRole.user), isTrue);
    },
  );

  test(
    'identity background retries keep earlier errors until success',
    () async {
      final repository = FakeIdentityRepository();
      final account = AccountCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      final libraries = LibrariesCubit(
        repository,
        identity: _identity,
        onSwitch: (_) async => null,
      );
      addTearDown(account.close);
      addTearDown(libraries.close);
      await account.load();
      await account.loadInvitations();
      await libraries.load();
      const failure = IdentityFailure(IdentityFailureKind.unavailable);
      repository.onList = () async => throw failure;
      repository.onInvitations = () async => throw failure;
      repository.onAccounts = () async => throw failure;
      await account.load(preserve: true);
      await account.loadInvitations(preserve: true);
      await libraries.load(preserve: true);
      final members = Completer<MemberPage>();
      final invitations = Completer<InvitationPage>();
      final accounts = Completer<AccountPage>();
      repository.onList = () => members.future;
      repository.onInvitations = () => invitations.future;
      repository.onAccounts = () => accounts.future;
      final reads = [
        account.load(preserve: true),
        account.loadInvitations(preserve: true),
        libraries.load(preserve: true),
      ];
      expect(account.error, failure.message);
      expect(account.invitationError, failure.message);
      expect(libraries.error, failure.message);
      members.complete(MemberPage(items: [], total: 0));
      invitations.complete(InvitationPage(items: [], total: 0));
      accounts.complete(AccountPage(items: [], total: 0));
      await Future.wait(reads);
      expect(account.error, isNull);
      expect(account.invitationError, isNull);
      expect(libraries.error, isNull);
    },
  );

  test('activity automatic reads retain empty snapshots and serialize explicit refresh', () async {
    final repository = _ActivityRepository();
    final activity = PersonalActivityCubit(repository);
    addTearDown(activity.close);
    repository.pending = Completer<PersonalActivity>();
    activity.setActive(true);
    expect(activity.state.loading, isTrue);
    repository.pending!.complete(repository.activity);
    await _flush();
    final snapshot = activity.state.activity;
    repository.pending = Completer<PersonalActivity>();
    final reading = activity.refresh(automatic: true);
    expect(activity.state.loading, isFalse);
    expect(activity.state.activity, same(snapshot));
    final repeated = activity.refresh(automatic: true);
    expect(repository.reads, 2);
    final explicit = activity.refresh();
    expect(activity.state.loading, isTrue);
    expect(repository.reads, 2);
    repository.pending!.complete(repository.activity);
    await Future.wait([reading, repeated, explicit]);
    expect(activity.state.loading, isFalse);
  });

  test(
    'load more waits for automatic identity refresh before appending its page',
    () async {
      final repository = FakeIdentityRepository()
        ..members = List.generate(
          51,
          (index) => AccountMember(
            id: 'member-$index',
            email: '$index@example.com',
            role: AccountRole.viewer,
            enabled: true,
            mustChangePassword: false,
          ),
        )
        ..invitations = List.generate(
          51,
          (index) => Invitation(
            id: 'invitation-$index',
            email: '$index@example.com',
            role: AccountRole.viewer,
            claims: [],
            createdAt: DateTime.utc(2026),
            expiresAt: DateTime.utc(2027),
            status: InvitationStatus.pending,
          ),
        )
        ..accounts = List.generate(
          51,
          (index) => AccountMembership(
            id: 'library-$index',
            name: 'Library $index',
            role: AccountRole.viewer,
            isOwner: false,
            claims: [],
            permissions: [IdentityPermission.readDocuments],
          ),
        )
        ..users = List.generate(
          51,
          (index) => SystemUser(
            id: 'user-$index',
            email: '$index@example.com',
            role: SystemRole.admin,
            createdAt: DateTime.utc(2026),
          ),
        );
      final account = AccountCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      final libraries = LibrariesCubit(
        repository,
        identity: _identity,
        onSwitch: (_) async => null,
      );
      final users = SystemUsersCubit(
        repository,
        identity: _identity,
        onSessionEnded: (_) {},
      );
      addTearDown(account.close);
      addTearDown(libraries.close);
      addTearDown(users.close);
      await account.load();
      await account.loadInvitations();
      await libraries.load();
      await users.load();
      final members = Completer<MemberPage>();
      final invitations = Completer<InvitationPage>();
      final accounts = Completer<AccountPage>();
      final system = Completer<SystemUserPage>();
      repository.onList = () => members.future;
      repository.onInvitations = () => invitations.future;
      repository.onAccounts = () => accounts.future;
      repository.onSystemUsers = (_, _) => system.future;
      final reads = [
        account.load(preserve: true),
        account.loadInvitations(preserve: true),
        libraries.load(preserve: true),
        users.load(preserve: true),
      ];
      final paging = [
        account.load(more: true),
        account.loadInvitations(more: true),
        libraries.load(more: true),
        users.load(more: true),
      ];
      await _flush();
      expect(account.members, hasLength(50));
      expect(account.invitations, hasLength(50));
      expect(libraries.accounts, hasLength(50));
      expect(users.users, hasLength(50));
      repository.onList = null;
      repository.onInvitations = null;
      repository.onAccounts = null;
      repository.onSystemUsers = null;
      members.complete(
        MemberPage(items: repository.members.take(50), total: 51),
      );
      invitations.complete(
        InvitationPage(items: repository.invitations.take(50), total: 51),
      );
      accounts.complete(
        AccountPage(items: repository.accounts.take(50), total: 51),
      );
      system.complete(
        SystemUserPage(
          items: repository.users.take(50),
          total: 51,
          adminCount: 51,
        ),
      );
      await Future.wait([...reads, ...paging]);
      expect(account.members, hasLength(51));
      expect(account.invitations, hasLength(51));
      expect(libraries.accounts, hasLength(51));
      expect(users.users, hasLength(51));
      expect(account.members.last.id, 'member-50');
      expect(account.invitations.last.id, 'invitation-50');
      expect(libraries.accounts.last.id, 'library-50');
      expect(users.users.last.id, 'user-50');
    },
  );

  test(
    'activity retry keeps failure evidence and cancellation fences old reads',
    () async {
      final repository = _ActivityRepository();
      final activity = PersonalActivityCubit(repository);
      addTearDown(activity.close);
      activity.setActive(true);
      await _flush();
      final snapshot = activity.state.activity;
      final failing = repository.pending = Completer<PersonalActivity>();
      final failureRead = activity.refresh(automatic: true);
      failing.completeError(
        const ActivityFailure(ActivityFailureKind.unavailable),
      );
      await failureRead;
      final error = activity.state.error;
      expect(error, isNotNull);
      final old = repository.pending = Completer<PersonalActivity>();
      final oldRead = activity.refresh(automatic: true);
      expect(activity.state.loading, isFalse);
      expect(activity.state.activity, same(snapshot));
      expect(activity.state.error, error);
      var cancelled = false;
      unawaited(repository.cancellation!.then((_) => cancelled = true));
      activity.setActive(false);
      await _flush();
      expect(cancelled, isTrue);
      repository.pending = null;
      activity.setActive(true);
      await _flush();
      expect(activity.state.error, isNull);
      old.complete(
        PersonalActivity(
          active: [],
          finished: [],
          activeTruncated: true,
          generatedAt: DateTime.utc(2025),
        ),
      );
      await oldRead;
      expect(activity.state.activity, same(repository.activity));
    },
  );
}
