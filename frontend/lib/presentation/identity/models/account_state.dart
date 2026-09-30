import '../../../domain/identity/models/identity.dart';

final class AccountState {
  AccountState({
    this.loading = false,
    this.saving = false,
    this.error,
    this.saveError,
    Iterable<AccountMember> members = const [],
    this.total = 0,
    Iterable<IdentityClaim> claims = const [],
    Iterable<Invitation> invitations = const [],
    this.invitationTotal = 0,
    this.loadingInvitations = false,
    this.invitationError,
  }) : members = List.unmodifiable(members),
       claims = List.unmodifiable(claims),
       invitations = List.unmodifiable(invitations);

  final bool loading;
  final bool saving;
  final String? error;
  final String? saveError;
  final List<AccountMember> members;
  final int total;
  final List<IdentityClaim> claims;
  final List<Invitation> invitations;
  final int invitationTotal;
  final bool loadingInvitations;
  final String? invitationError;
}
