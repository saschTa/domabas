import 'dart:convert';

enum AccountRole { admin, user, viewer }

enum SystemRole { admin, user }

abstract final class IdentityPermission {
  static const useChat = 'chat:use';
  static const manageChat = 'system:chat:manage';
  static const readInvoices = 'invoices:read';
  static const connectRealtime = 'realtime:connect';
  static const manageEmail = 'email:manage';
  static const importPaperless = 'paperless:import';
  static const managePaperless = 'system:paperless:manage';
  static const manageWorkloads = 'system:workloads:manage';
  static const uploadDocuments = 'documents:upload';
  static const readOwnActivity = 'activity:read:own';
  static const readDocuments = 'documents:read';
  static const searchDocuments = 'documents:search';
  static const createDocuments = 'documents:create';
  static const downloadDocuments = 'documents:download';
  static const readDocumentThumbnails = 'documents:thumbnails:read';
  static const updateDocuments = 'documents:update';
  static const readDocumentOcr = 'documents:ocr:read';
  static const updateDocumentOcr = 'documents:ocr:update';
  static const deleteDocuments = 'documents:delete';
  static const retryDocuments = 'documents:retry';
  static const unlockDocuments = 'documents:unlock';
  static const manageUsers = 'users:manage';
  static const manageSystemUsers = 'system:users:manage';
  static const readDocumentJobs = 'documents:jobs:read';
  static const reindexDocuments = 'documents:reindex';
  static const manageDocumentProcessing = 'system:document-processing:manage';
}

final class Identity {
  Identity({
    required this.userId,
    required this.email,
    required this.accountId,
    required this.accountName,
    required this.role,
    required this.mustChangePassword,
    this.isOwner = false,
    this.systemRole = SystemRole.user,
    Iterable<String> claims = const [],
    required Iterable<String> permissions,
  }) : permissions = Set.unmodifiable(permissions),
       claims = Set.unmodifiable(claims);

  final String userId;
  final String email;
  final String accountId;
  final String accountName;
  final AccountRole role;
  final bool mustChangePassword;
  final bool isOwner;
  final SystemRole systemRole;
  final Set<String> claims;
  final Set<String> permissions;

  bool allows(String permission) =>
      !mustChangePassword && permissions.contains(permission);
}

final class AuthSession {
  const AuthSession({
    required this.token,
    required this.expiresAt,
    required this.identity,
  });

  final String token;
  final DateTime? expiresAt;
  final Identity identity;
}

final class AccountMember {
  AccountMember({
    required this.id,
    required this.email,
    required this.role,
    required this.enabled,
    required this.mustChangePassword,
    this.isOwner = false,
    Iterable<String> claims = const [],
    Iterable<String> permissions = const [],
  }) : claims = Set.unmodifiable(claims),
       permissions = Set.unmodifiable(permissions);

  final String id;
  final String email;
  final AccountRole role;
  final bool enabled;
  final bool mustChangePassword;
  final bool isOwner;
  final Set<String> claims;
  final Set<String> permissions;
}

final class AccountMembership {
  AccountMembership({
    required this.id,
    required this.name,
    required this.role,
    required this.isOwner,
    required Iterable<String> claims,
    required Iterable<String> permissions,
  }) : claims = Set.unmodifiable(claims),
       permissions = Set.unmodifiable(permissions);
  final String id;
  final String name;
  final AccountRole role;
  final bool isOwner;
  final Set<String> claims;
  final Set<String> permissions;
}

final class AccountPage {
  AccountPage({required Iterable<AccountMembership> items, required this.total})
    : items = List.unmodifiable(items);
  final List<AccountMembership> items;
  final int total;
}

enum IdentityClaimScope { namespace, system }

final class IdentityClaim {
  IdentityClaim({
    required this.id,
    required this.label,
    required this.scope,
    required Iterable<String> roles,
  }) : roles = Set.unmodifiable(roles);
  final String id;
  final String label;
  final IdentityClaimScope scope;
  final Set<String> roles;

  bool includesRole(AccountRole role) =>
      scope == IdentityClaimScope.namespace && roles.contains(role.name);
}

enum InvitationStatus { pending, accepted, revoked, expired }

final class Invitation {
  Invitation({
    required this.id,
    required this.email,
    required this.role,
    required Iterable<String> claims,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
  }) : claims = Set.unmodifiable(claims);
  final String id;
  final String email;
  final AccountRole role;
  final Set<String> claims;
  final DateTime createdAt;
  final DateTime expiresAt;
  final InvitationStatus status;
}

final class IssuedInvitation {
  const IssuedInvitation({required this.invitation, required this.code});
  final Invitation invitation;
  final String code;
}

final class InvitationPage {
  InvitationPage({required Iterable<Invitation> items, required this.total})
    : items = List.unmodifiable(items);
  final List<Invitation> items;
  final int total;
}

final class SystemUser {
  const SystemUser({
    required this.id,
    required this.email,
    required this.role,
    required this.createdAt,
  });
  final String id;
  final String email;
  final SystemRole role;
  final DateTime createdAt;
}

final class SystemUserPage {
  SystemUserPage({
    required Iterable<SystemUser> items,
    required this.total,
    required this.adminCount,
  }) : items = List.unmodifiable(items);
  final List<SystemUser> items;
  final int total;
  final int adminCount;
}

final class MemberPage {
  MemberPage({required Iterable<AccountMember> items, required this.total})
    : items = List.unmodifiable(items);

  final List<AccountMember> items;
  final int total;
}

abstract final class IdentityCredentials {
  static String? validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.length > 254 ||
        !RegExp(r'^[^\s@<>(),;:"\\]+@[^\s@<>(),;:"\\]+$').hasMatch(email) ||
        email.codeUnits.any((character) => character < 33 || character > 126)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    final password = value ?? '';
    if (password.runes.length < 8 ||
        password.runes.length > 128 ||
        utf8.encode(password).length > 512) {
      return 'Use 8–128 characters for your password.';
    }
    return null;
  }

  static String? validateAccountName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty || name.runes.length > 100) {
      return 'Enter an account name of 1–100 characters.';
    }
    return null;
  }
}
