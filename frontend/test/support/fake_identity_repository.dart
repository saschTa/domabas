import 'dart:async';

import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas/domain/identity/interfaces/identity_repository.dart';

AuthSession testSession({
  String suffix = 'a',
  AccountRole role = AccountRole.admin,
  bool mustChangePassword = false,
  bool? isOwner,
  SystemRole systemRole = SystemRole.user,
  Iterable<String> extraPermissions = const [],
}) => AuthSession(
  token: suffix.padRight(43, 'A'),
  expiresAt: DateTime.utc(2100),
  identity: Identity(
    userId: 'user-$suffix',
    email: '$suffix@example.com',
    accountId: 'account-$suffix',
    accountName: 'Account $suffix',
    role: role,
    isOwner: isOwner ?? role == AccountRole.admin,
    systemRole: systemRole,
    mustChangePassword: mustChangePassword,
    permissions: [
      IdentityPermission.readDocuments,
      if (role != AccountRole.viewer) IdentityPermission.createDocuments,
      if (role == AccountRole.admin) IdentityPermission.manageUsers,
      if (systemRole == SystemRole.admin) IdentityPermission.manageSystemUsers,
      ...extraPermissions,
    ],
  ),
);

final class FakeAuthRepository implements AuthRepository {
  AuthSession next = testSession();
  AuthSession? saved;
  Future<AuthSession?> Function()? onRestore;
  Future<void> Function(AuthSession)? onRemember;
  Future<void> Function()? onForget;
  Future<void> Function(AuthSession)? onRevoke;
  final List<AuthSession> revoked = [];
  Future<AuthSession> Function()? onLogin;
  String? lastPassword;
  @override
  Future<AuthSession?> restore() async =>
      onRestore == null ? saved : await onRestore!();
  @override
  Future<void> remember(AuthSession session) async {
    if (onRemember != null) await onRemember!(session);
    saved = session;
  }

  @override
  Future<void> forget() async {
    if (onForget != null) await onForget!();
    saved = null;
  }

  @override
  Future<void> revoke(AuthSession session) async {
    revoked.add(session);
    if (onRevoke != null) await onRevoke!(session);
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    lastPassword = password;
    return onLogin == null ? next : await onLogin!();
  }

  @override
  Future<AuthSession> register({
    required String accountName,
    required String email,
    required String password,
  }) => login(email: email, password: password);
}

final class FakeIdentityRepository implements IdentityRepository {
  Future<Identity> Function()? onCurrentIdentity;
  @override
  Future<Identity> currentIdentity() async {
    if (onCurrentIdentity != null) return onCurrentIdentity!();
    throw const IdentityFailure(IdentityFailureKind.unavailable);
  }

  Future<void> Function()? onLogout;
  Future<MemberPage> Function()? onList;
  Future<AccountPage> Function()? onAccounts;
  Future<InvitationPage> Function()? onInvitations;
  Future<SystemUserPage> Function(int limit, int offset)? onSystemUsers;
  Future<AuthSession> Function(String)? onSwitch;
  Future<AccountMembership> Function(String)? onAccept;
  IdentityFailure? changeFailure;
  IdentityFailure? systemFailure;
  bool passwordChanged = false;
  List<AccountMember> members = [];
  List<AccountMembership> accounts = [];
  List<Invitation> invitations = [];
  List<SystemUser> users = [];
  List<IdentityClaim> catalog = [
    IdentityClaim(
      id: IdentityPermission.readDocuments,
      label: 'Read documents',
      scope: IdentityClaimScope.namespace,
      roles: ['admin', 'user', 'viewer'],
    ),
    IdentityClaim(
      id: IdentityPermission.createDocuments,
      label: 'Create documents',
      scope: IdentityClaimScope.namespace,
      roles: ['admin', 'user'],
    ),
    IdentityClaim(
      id: IdentityPermission.manageUsers,
      label: 'Manage library members',
      scope: IdentityClaimScope.namespace,
      roles: ['admin'],
    ),
    IdentityClaim(
      id: IdentityPermission.manageSystemUsers,
      label: 'Manage system users',
      scope: IdentityClaimScope.system,
      roles: ['admin'],
    ),
  ];
  int creations = 0;
  int systemUpdates = 0;
  @override
  Future<void> logout() async => onLogout?.call();
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (changeFailure case final failure?) throw failure;
    passwordChanged = true;
  }

  @override
  Future<MemberPage> listMembers({int limit = 50, int offset = 0}) async =>
      onList == null
      ? MemberPage(
          items: members.skip(offset).take(limit),
          total: members.length,
        )
      : await onList!();
  @override
  Future<AccountMember> createMember({
    required String email,
    required String password,
    required AccountRole role,
    Set<String> claims = const {},
  }) async {
    creations++;
    final member = AccountMember(
      id: 'created-$creations',
      email: email,
      role: role,
      enabled: true,
      mustChangePassword: true,
      claims: claims,
    );
    members.add(member);
    return member;
  }

  @override
  Future<AccountMember> updateMember({
    required String id,
    required AccountRole role,
    required bool enabled,
    Set<String> claims = const {},
  }) async {
    final old = members.singleWhere((member) => member.id == id);
    final updated = AccountMember(
      id: old.id,
      email: old.email,
      role: role,
      enabled: enabled,
      mustChangePassword: old.mustChangePassword,
      claims: claims,
      permissions: old.permissions,
      isOwner: old.isOwner,
    );
    members = members
        .map((member) => member.id == id ? updated : member)
        .toList();
    return updated;
  }

  @override
  Future<AccountPage> listAccounts({int limit = 50, int offset = 0}) async =>
      onAccounts != null
      ? await onAccounts!()
      : AccountPage(
          items: accounts.skip(offset).take(limit),
          total: accounts.length,
        );
  @override
  Future<AuthSession> switchAccount(String accountId) => onSwitch!(accountId);
  @override
  Future<List<IdentityClaim>> listClaims() async => List.unmodifiable(catalog);
  @override
  Future<InvitationPage> listInvitations({
    int limit = 50,
    int offset = 0,
  }) async => onInvitations != null
      ? await onInvitations!()
      : InvitationPage(
          items: invitations.skip(offset).take(limit),
          total: invitations.length,
        );
  @override
  Future<IssuedInvitation> createInvitation({
    required String email,
    required AccountRole role,
    required Set<String> claims,
  }) async {
    final invitation = Invitation(
      id: 'invitation-${invitations.length}',
      email: email,
      role: role,
      claims: claims,
      createdAt: DateTime.utc(2026),
      expiresAt: DateTime.utc(2026, 1, 8),
      status: InvitationStatus.pending,
    );
    invitations.add(invitation);
    return IssuedInvitation(invitation: invitation, code: 'A' * 43);
  }

  @override
  Future<void> revokeInvitation(String id) async {
    invitations = invitations
        .map(
          (value) => value.id != id
              ? value
              : Invitation(
                  id: value.id,
                  email: value.email,
                  role: value.role,
                  claims: value.claims,
                  createdAt: value.createdAt,
                  expiresAt: value.expiresAt,
                  status: InvitationStatus.revoked,
                ),
        )
        .toList();
  }

  @override
  Future<AccountMembership> acceptInvitation(String code) => onAccept!(code);
  @override
  Future<SystemUserPage> listSystemUsers({
    int limit = 50,
    int offset = 0,
  }) async => onSystemUsers != null
      ? await onSystemUsers!(limit, offset)
      : SystemUserPage(
          items: users.skip(offset).take(limit),
          total: users.length,
          adminCount: users
              .where((user) => user.role == SystemRole.admin)
              .length,
        );
  @override
  Future<SystemUser> updateSystemUser(String id, SystemRole role) async {
    systemUpdates++;
    if (systemFailure case final failure?) throw failure;
    final old = users.singleWhere((value) => value.id == id);
    final updated = SystemUser(
      id: id,
      email: old.email,
      role: role,
      createdAt: old.createdAt,
    );
    users = users.map((value) => value.id == id ? updated : value).toList();
    return updated;
  }
}
