import '../models/identity.dart';

abstract interface class AuthRepository {
  Future<AuthSession?> restore();
  Future<void> remember(AuthSession session);
  Future<void> forget();
  Future<void> revoke(AuthSession session);
  Future<AuthSession> login({required String email, required String password});
  Future<AuthSession> register({
    required String accountName,
    required String email,
    required String password,
  });
}

abstract interface class IdentityRepository {
  Future<Identity> currentIdentity();
  Future<void> logout();
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
  Future<MemberPage> listMembers({int limit = 50, int offset = 0});
  Future<AccountMember> createMember({
    required String email,
    required String password,
    required AccountRole role,
    Set<String> claims = const {},
  });
  Future<AccountMember> updateMember({
    required String id,
    required AccountRole role,
    required bool enabled,
    Set<String> claims = const {},
  });
  Future<AccountPage> listAccounts({int limit = 50, int offset = 0});
  Future<AuthSession> switchAccount(String accountId);
  Future<List<IdentityClaim>> listClaims();
  Future<InvitationPage> listInvitations({int limit = 50, int offset = 0});
  Future<IssuedInvitation> createInvitation({
    required String email,
    required AccountRole role,
    required Set<String> claims,
  });
  Future<void> revokeInvitation(String id);
  Future<AccountMembership> acceptInvitation(String code);
  Future<SystemUserPage> listSystemUsers({int limit = 50, int offset = 0});
  Future<SystemUser> updateSystemUser(String id, SystemRole role);
}
