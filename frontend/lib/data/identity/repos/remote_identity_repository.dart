import 'dart:async';
import 'dart:convert';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/identity/models/identity.dart';
import '../../../domain/identity/models/identity_failure.dart';
import '../../../domain/identity/interfaces/identity_repository.dart';
import '../../../domain/identity/interfaces/session_store.dart';
import '../datasources/identity_remote_data_source.dart';

final class RemoteIdentityRepository
    implements AuthRepository, IdentityRepository {
  RemoteIdentityRepository(this._source, {this._sessionStore});

  final IdentityRemoteDataSource _source;
  final SessionStore? _sessionStore;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  Future<AuthSession?> restore() async {
    final store = _sessionStore;
    if (store == null || await store.isSignedOut()) return null;
    final token = await store.readToken();
    try {
      return await _translate(() async {
        final value = await _source.restore(token);
        return value == null ? null : _identitySessionMapper(value);
      });
    } on IdentityFailure catch (failure) {
      if (failure.kind != IdentityFailureKind.unauthorized) rethrow;
      await store.clear();
      return null;
    }
  }

  @override
  Future<void> remember(AuthSession session) async =>
      _sessionStore?.saveToken(session.token);

  @override
  Future<void> forget() async => _sessionStore?.clear();

  @override
  Future<void> revoke(AuthSession session) =>
      _translate(() => _source.revoke(session.token));

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) => _translate(
    () async => _identitySessionMapper(
      await _source.login(email.trim().toLowerCase(), password),
    ),
  );

  @override
  Future<AuthSession> register({
    required String accountName,
    required String email,
    required String password,
  }) => _translate(
    () async => _identitySessionMapper(
      await _source.register(
        accountName.trim(),
        email.trim().toLowerCase(),
        password,
      ),
    ),
  );

  @override
  Future<Identity> currentIdentity() =>
      _translate(() async => _identityMapper(await _source.currentIdentity()));

  @override
  Future<void> logout() => _translate(_source.logout);

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _translate(() => _source.changePassword(currentPassword, newPassword));

  @override
  Future<MemberPage> listMembers({int limit = 50, int offset = 0}) =>
      _translate(() async {
        final page = await _source.listMembers(limit, offset);
        if (page.total < page.items.length || page.total < 0) {
          throw const FormatException('Invalid member total');
        }
        return MemberPage(
          items: page.items.map(_identityMemberMapper),
          total: page.total,
        );
      });

  @override
  Future<AccountMember> createMember({
    required String email,
    required String password,
    required AccountRole role,
    Set<String> claims = const {},
  }) => _translate(
    () async => _identityMemberMapper(
      await _source.createMember(
        email.trim().toLowerCase(),
        password,
        api.AccountRole.values.byName(role.name),
        Set.of(claims),
      ),
    ),
  );

  @override
  Future<AccountMember> updateMember({
    required String id,
    required AccountRole role,
    required bool enabled,
    Set<String> claims = const {},
  }) => _translate(
    () async => _identityMemberMapper(
      await _source.updateMember(
        id,
        api.AccountRole.values.byName(role.name),
        enabled,
        Set.of(claims),
      ),
    ),
  );

  AuthSession _identitySessionMapper(api.AuthSession value) {
    final decoded = base64Url.decode(base64Url.normalize(value.token));
    if (decoded.length != 32 ||
        base64Url.encode(decoded).replaceAll('=', '') != value.token) {
      throw const FormatException('Invalid session token');
    }
    return AuthSession(
      token: value.token,
      expiresAt: value.expiresAt?.toUtc(),
      identity: _identityMapper(value.identity),
    );
  }

  Identity _identityMapper(api.CurrentIdentity identity) {
    if (!_uuid.hasMatch(identity.user.id) ||
        !_uuid.hasMatch(identity.account.id) ||
        IdentityCredentials.validateEmail(identity.user.email) != null ||
        IdentityCredentials.validateAccountName(identity.account.name) !=
            null) {
      throw const FormatException('Invalid identity');
    }
    return Identity(
      userId: identity.user.id,
      email: identity.user.email,
      accountId: identity.account.id,
      accountName: identity.account.name,
      role: AccountRole.values.byName(identity.role.name),
      mustChangePassword: identity.user.mustChangePassword,
      permissions: identity.permissions,
      claims: identity.claims,
      isOwner: identity.isOwner,
      systemRole: SystemRole.values.byName(identity.systemRole.name),
    );
  }

  AccountMember _identityMemberMapper(api.AccountUser value) {
    if (!_uuid.hasMatch(value.id) ||
        IdentityCredentials.validateEmail(value.email) != null) {
      throw const FormatException('Invalid member');
    }
    return AccountMember(
      id: value.id,
      email: value.email,
      role: AccountRole.values.byName(value.role.name),
      enabled: value.enabled,
      mustChangePassword: value.mustChangePassword,
      isOwner: value.isOwner,
      claims: value.claims,
      permissions: value.permissions,
    );
  }

  void _page(int total, int count) {
    if (total < count || total < 0) {
      throw const FormatException('Invalid list total');
    }
  }

  AccountMembership _identityMembershipMapper(api.AccountMembership value) {
    if (!_uuid.hasMatch(value.account.id) ||
        IdentityCredentials.validateAccountName(value.account.name) != null) {
      throw const FormatException('Invalid namespace');
    }
    return AccountMembership(
      id: value.account.id,
      name: value.account.name,
      role: AccountRole.values.byName(value.role.name),
      isOwner: value.isOwner,
      claims: value.claims,
      permissions: value.permissions,
    );
  }

  Invitation _identityInvitationMapper(api.Invitation value) {
    if (!_uuid.hasMatch(value.id) ||
        IdentityCredentials.validateEmail(value.email) != null) {
      throw const FormatException('Invalid invitation');
    }
    return Invitation(
      id: value.id,
      email: value.email,
      role: AccountRole.values.byName(value.role.name),
      claims: value.claims,
      createdAt: value.createdAt.toUtc(),
      expiresAt: value.expiresAt.toUtc(),
      status: InvitationStatus.values.byName(value.status.name),
    );
  }

  SystemUser _identitySystemUserMapper(api.SystemUser value) {
    if (!_uuid.hasMatch(value.id) ||
        IdentityCredentials.validateEmail(value.email) != null) {
      throw const FormatException('Invalid user');
    }
    return SystemUser(
      id: value.id,
      email: value.email,
      role: SystemRole.values.byName(value.role.name),
      createdAt: value.createdAt.toUtc(),
    );
  }

  @override
  Future<AccountPage> listAccounts({int limit = 50, int offset = 0}) =>
      _translate(() async {
        final page = await _source.listAccounts(limit, offset);
        _page(page.total, page.items.length);
        return AccountPage(
          items: page.items.map(_identityMembershipMapper),
          total: page.total,
        );
      });
  @override
  Future<AuthSession> switchAccount(String accountId) => _translate(
    () async => _identitySessionMapper(await _source.switchAccount(accountId)),
  );
  @override
  Future<List<IdentityClaim>> listClaims() => _translate(
    () async => List.unmodifiable(
      (await _source.listClaims()).items.map(
        (value) => IdentityClaim(
          id: value.id,
          label: value.label,
          scope: IdentityClaimScope.values.byName(value.scope.name),
          roles: value.roles,
        ),
      ),
    ),
  );
  @override
  Future<InvitationPage> listInvitations({int limit = 50, int offset = 0}) =>
      _translate(() async {
        final page = await _source.listInvitations(limit, offset);
        _page(page.total, page.items.length);
        return InvitationPage(
          items: page.items.map(_identityInvitationMapper),
          total: page.total,
        );
      });
  @override
  Future<IssuedInvitation> createInvitation({
    required String email,
    required AccountRole role,
    required Set<String> claims,
  }) => _translate(() async {
    final value = await _source.createInvitation(
      email.trim().toLowerCase(),
      api.AccountRole.values.byName(role.name),
      Set.of(claims),
    );
    final bytes = base64Url.decode(base64Url.normalize(value.code));
    if (bytes.length != 32 ||
        base64Url.encode(bytes).replaceAll('=', '') != value.code) {
      throw const FormatException('Invalid invitation code');
    }
    return IssuedInvitation(
      invitation: _identityInvitationMapper(value.invitation),
      code: value.code,
    );
  });
  @override
  Future<void> revokeInvitation(String id) =>
      _translate(() => _source.revokeInvitation(id));
  @override
  Future<AccountMembership> acceptInvitation(String code) => _translate(
    () async =>
        _identityMembershipMapper(await _source.acceptInvitation(code.trim())),
  );
  @override
  Future<SystemUserPage> listSystemUsers({int limit = 50, int offset = 0}) =>
      _translate(() async {
        final page = await _source.listSystemUsers(limit, offset);
        _page(page.total, page.items.length);
        if (page.adminCount < 0 ||
            page.adminCount > page.total ||
            page.adminCount <
                page.items
                    .where((user) => user.role == api.SystemRole.admin)
                    .length) {
          throw const FormatException('Invalid administrator count');
        }
        return SystemUserPage(
          items: page.items.map(_identitySystemUserMapper),
          total: page.total,
          adminCount: page.adminCount,
        );
      });
  @override
  Future<SystemUser> updateSystemUser(String id, SystemRole role) => _translate(
    () async => _identitySystemUserMapper(
      await _source.updateSystemUser(
        id,
        api.SystemRole.values.byName(role.name),
      ),
    ),
  );

  Future<T> _translate<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on api.ApiException catch (error) {
      if (error.innerException != null || error.code >= 500) {
        throw const IdentityFailure(IdentityFailureKind.unavailable);
      }
      String? code;
      try {
        final body = jsonDecode(error.message ?? '');
        if (body is Map && body['code'] is String) {
          code = body['code'] as String;
        }
      } on FormatException {
        code = null;
      }
      throw IdentityFailure(switch ((error.code, code)) {
        (400 || 401, 'invalid_credentials') =>
          IdentityFailureKind.invalidCredentials,
        (401, _) => IdentityFailureKind.unauthorized,
        (403, 'password_change_required') =>
          IdentityFailureKind.passwordChangeRequired,
        (403, _) => IdentityFailureKind.forbidden,
        (404, _) => IdentityFailureKind.notFound,
        (409, _) => IdentityFailureKind.conflict,
        (429, _) => IdentityFailureKind.rateLimited,
        (400 || 413 || 415 || 422, _) => IdentityFailureKind.rejected,
        _ => IdentityFailureKind.invalidResponse,
      });
    } on TimeoutException {
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    } on http.ClientException {
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    } on FormatException {
      throw const IdentityFailure(IdentityFailureKind.invalidResponse);
    }
  }
}
