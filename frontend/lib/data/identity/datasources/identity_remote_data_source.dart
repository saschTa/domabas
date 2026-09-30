import 'dart:async';
import 'dart:convert';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

final class IdentityRemoteDataSource {
  IdentityRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 15),
  });

  final api.IdentityApi _api;
  final Duration timeout;

  Future<api.CurrentIdentity> currentIdentity() =>
      _body((abort) => _api.currentIdentity(abortTrigger: abort));

  Future<api.AuthSession?> restore(String? token) => _session(
    (abort) => _api.restoreSessionWithHttpInfo(
      authorization: token == null ? null : 'Bearer $token',
      abortTrigger: abort,
    ),
    allowEmpty: true,
  );

  Future<api.AuthSession> login(String email, String password) async =>
      (await _session(
        (abort) => _api.loginWithHttpInfo(
          api.Login(email: email, password: password),
          abortTrigger: abort,
        ),
      ))!;

  Future<api.AuthSession> register(
    String accountName,
    String email,
    String password,
  ) async => (await _session(
    (abort) => _api.registerWithHttpInfo(
      api.Registration(
        accountName: accountName,
        email: email,
        password: password,
      ),
      abortTrigger: abort,
    ),
  ))!;

  Future<void> logout() =>
      _request((abort) => _api.logout(abortTrigger: abort));

  Future<void> revoke(String token) => _request(
    (abort) => _api.logout(authorization: 'Bearer $token', abortTrigger: abort),
  );

  Future<void> changePassword(String currentPassword, String newPassword) =>
      _request(
        (abort) => _api.changePassword(
          api.PasswordChange(
            currentPassword: currentPassword,
            newPassword: newPassword,
          ),
          abortTrigger: abort,
        ),
      );

  Future<api.AccountUserList> listMembers(int limit, int offset) => _body(
    (abort) => _api.listAccountUsers(
      limit: limit,
      offset: offset,
      abortTrigger: abort,
    ),
  );

  Future<api.AccountUser> createMember(
    String email,
    String password,
    api.AccountRole role,
    Set<String> claims,
  ) => _body(
    (abort) => _api.createAccountUser(
      api.CreateAccountUser(
        email: email,
        password: password,
        role: role,
        claims: claims,
      ),
      abortTrigger: abort,
    ),
  );

  Future<api.AccountUser> updateMember(
    String id,
    api.AccountRole role,
    bool enabled,
    Set<String> claims,
  ) => _body(
    (abort) => _api.updateAccountUser(
      id,
      api.UpdateAccountUser(role: role, enabled: enabled, claims: claims),
      abortTrigger: abort,
    ),
  );

  Future<api.AccountMembershipList> listAccounts(int limit, int offset) =>
      _body(
        (abort) => _api.listAccounts(
          limit: limit,
          offset: offset,
          abortTrigger: abort,
        ),
      );
  Future<api.AuthSession> switchAccount(String id) async => (await _session(
    (abort) => _api.switchAccountWithHttpInfo(
      api.SwitchAccount(accountId: id),
      abortTrigger: abort,
    ),
  ))!;
  Future<api.ClaimList> listClaims() =>
      _body((abort) => _api.listClaims(abortTrigger: abort));
  Future<api.InvitationList> listInvitations(int limit, int offset) => _body(
    (abort) =>
        _api.listInvitations(limit: limit, offset: offset, abortTrigger: abort),
  );
  Future<api.IssuedInvitation> createInvitation(
    String email,
    api.AccountRole role,
    Set<String> claims,
  ) => _body(
    (abort) => _api.createInvitation(
      api.CreateInvitation(email: email, role: role, claims: claims),
      abortTrigger: abort,
    ),
  );
  Future<void> revokeInvitation(String id) =>
      _request((abort) => _api.revokeInvitation(id, abortTrigger: abort));
  Future<api.AccountMembership> acceptInvitation(String code) => _body(
    (abort) => _api.acceptInvitation(
      api.AcceptInvitation(code: code),
      abortTrigger: abort,
    ),
  );
  Future<api.SystemUserList> listSystemUsers(int limit, int offset) => _body(
    (abort) =>
        _api.listSystemUsers(limit: limit, offset: offset, abortTrigger: abort),
  );
  Future<api.SystemUser> updateSystemUser(String id, api.SystemRole role) =>
      _body(
        (abort) => _api.updateSystemUser(
          id,
          api.UpdateSystemUser(role: role),
          abortTrigger: abort,
        ),
      );

  Future<api.AuthSession?> _session(
    Future<http.Response> Function(Future<void>) send, {
    bool allowEmpty = false,
  }) => _request((abort) async {
    final response = await send(abort);
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 400) {
      throw api.ApiException(response.statusCode, body);
    }
    if (allowEmpty && response.statusCode == 204) return null;
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || !decoded.containsKey('expiresAt')) {
      throw const FormatException('Missing session expiry');
    }
    final expiry = decoded['expiresAt'];
    if (expiry != null &&
        (expiry is! String ||
            !RegExp(
              r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$',
            ).hasMatch(expiry) ||
            DateTime.tryParse(expiry) == null)) {
      throw const FormatException('Invalid session expiry');
    }
    final result = api.AuthSession.fromJson(decoded);
    if (result == null) throw const FormatException('Missing session');
    return result;
  });

  Future<T> _body<T>(Future<T?> Function(Future<void>) send) async {
    final result = await _request(send);
    if (result == null) throw const FormatException('Missing response body');
    return result;
  }

  Future<T> _request<T>(Future<T> Function(Future<void>) send) async {
    final abort = Completer<void>();
    final timer = Timer(timeout, abort.complete);
    try {
      return await send(abort.future).timeout(timeout);
    } on TypeError {
      throw const FormatException('Response does not match the API contract');
    } on AssertionError {
      throw const FormatException('Response is missing required fields');
    } on ArgumentError {
      throw const FormatException(
        'Response contains an unknown role or status',
      );
    } finally {
      timer.cancel();
    }
  }
}
