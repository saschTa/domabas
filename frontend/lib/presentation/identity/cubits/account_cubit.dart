import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/identity/models/identity.dart';
import '../../../domain/identity/models/identity_failure.dart';
import '../../../domain/identity/interfaces/identity_repository.dart';

import '../models/account_state.dart';

export '../models/account_state.dart';

final class AccountCubit extends Cubit<AccountState> {
  AccountCubit(
    this._repository, {
    required this.identity,
    required this.onSessionEnded,
  }) : super(AccountState());

  final IdentityRepository _repository;
  Identity identity;
  void updateDisplay(Identity value) {
    identity = value;
    _publish();
  }

  final void Function(String) onSessionEnded;
  late final _refresh = AutomaticRefresh(
    read: () async {
      await load(preserve: true);
      await loadInvitations(preserve: true);
    },
    busy: () => _loading || _loadingInvitations || _saving,
    interval: () => Duration(seconds: _error == null ? 1 : 30),
  );
  void setActive(bool value) => _refresh.setActive(value);
  void invalidate() => _refresh.invalidate();
  bool _disposed = false;
  bool _loading = false;
  bool _backgroundLoading = false;
  bool _hasMembersSnapshot = false;
  Completer<void>? _membersReadDone;
  bool _saving = false;
  String? _error;
  String? _saveError;
  List<AccountMember> _members = const [];
  int _total = 0;
  List<IdentityClaim> _claims = const [];
  List<Invitation> _invitations = const [];
  int _invitationTotal = 0;
  bool _loadingInvitations = false;
  bool _backgroundLoadingInvitations = false;
  bool _hasInvitationsSnapshot = false;
  Completer<void>? _invitationsReadDone;
  String? _invitationError;

  bool get loading => state.loading;
  bool get saving => state.saving;
  String? get error => state.error;
  String? get saveError => state.saveError;
  List<AccountMember> get members => state.members;
  int get total => state.total;
  bool get canLoadMore => members.length < total;
  List<IdentityClaim> get claims => state.claims;
  List<Invitation> get invitations => state.invitations;
  bool get loadingInvitations => state.loadingInvitations;
  String? get invitationError => state.invitationError;
  bool get canLoadMoreInvitations => _invitations.length < _invitationTotal;

  Set<String> roleClaims(AccountRole role) => Set.unmodifiable(
    _claims.where((claim) => claim.includesRole(role)).map((claim) => claim.id),
  );

  Set<String> effectiveClaims(
    AccountRole role,
    Iterable<String> additionalClaims,
  ) => Set.unmodifiable({...roleClaims(role), ...additionalClaims});

  bool canAssignRole(AccountRole role) =>
      !_disposed &&
      !loading &&
      _error == null &&
      _claims.isNotEmpty &&
      identity.allows(IdentityPermission.manageUsers) &&
      roleClaims(role).every(identity.allows);

  Future<void> load({bool more = false, bool preserve = false}) async {
    if (_disposed || (preserve && _saving)) return;
    if (_loading) {
      if (preserve || !_backgroundLoading) return;
      _backgroundLoading = false;
      _publish();
      await _membersReadDone!.future;
      if (!more || _disposed || _loading || _saving || _error != null) return;
    }
    _loading = true;
    _backgroundLoading = preserve && _hasMembersSnapshot;
    final readDone = _membersReadDone = Completer<void>();
    if (!_backgroundLoading) _error = null;
    _publish();
    try {
      final catalog = await _repository.listClaims();
      final target = preserve ? _members.length : 0;
      var page = await _repository.listMembers(
        offset: more ? _members.length : 0,
      );
      final items = <AccountMember>[...page.items];
      while (!_disposed &&
          preserve &&
          items.length < target &&
          items.length < page.total &&
          page.items.isNotEmpty) {
        page = await _repository.listMembers(offset: items.length);
        items.addAll(page.items);
      }
      if (_disposed) return;
      _claims = List.unmodifiable(
        catalog.where((claim) => claim.scope == IdentityClaimScope.namespace),
      );
      _members = List.unmodifiable(
        {
          for (final item in [if (more) ..._members, ...items]) item.id: item,
        }.values,
      );
      _total = page.total;
      _hasMembersSnapshot = true;
      _error = null;
    } on IdentityFailure catch (failure) {
      if (!_disposed) _error = failure.message;
    } finally {
      _loading = false;
      _backgroundLoading = false;
      _publish();
      readDone.complete();
    }
  }

  Future<void> loadInvitations({
    bool more = false,
    bool preserve = false,
  }) async {
    if (_disposed || (preserve && _saving)) return;
    if (_loadingInvitations) {
      if (preserve || !_backgroundLoadingInvitations) return;
      _backgroundLoadingInvitations = false;
      _publish();
      await _invitationsReadDone!.future;
      if (!more ||
          _disposed ||
          _loadingInvitations ||
          _saving ||
          _invitationError != null) {
        return;
      }
    }
    _loadingInvitations = true;
    _backgroundLoadingInvitations = preserve && _hasInvitationsSnapshot;
    final readDone = _invitationsReadDone = Completer<void>();
    if (!_backgroundLoadingInvitations) _invitationError = null;
    _publish();
    try {
      final target = preserve ? _invitations.length : 0;
      var page = await _repository.listInvitations(
        offset: more ? _invitations.length : 0,
      );
      final items = <Invitation>[...page.items];
      while (!_disposed &&
          preserve &&
          items.length < target &&
          items.length < page.total &&
          page.items.isNotEmpty) {
        page = await _repository.listInvitations(offset: items.length);
        items.addAll(page.items);
      }
      if (_disposed) return;
      _invitations = List.unmodifiable(
        {
          for (final item in [if (more) ..._invitations, ...items])
            item.id: item,
        }.values,
      );
      _invitationTotal = page.total;
      _hasInvitationsSnapshot = true;
      _invitationError = null;
    } on IdentityFailure catch (failure) {
      if (!_disposed) _invitationError = failure.message;
    } finally {
      _loadingInvitations = false;
      _backgroundLoadingInvitations = false;
      _publish();
      readDone.complete();
    }
  }

  Future<IssuedInvitation?> invite(
    String email,
    AccountRole role,
    Set<String> claims,
  ) async {
    if (!await _waitForBackgroundReads() ||
        !_canGrant(role) ||
        _invitationError != null) {
      return null;
    }
    IssuedInvitation? issued;
    final saved = await _save(() async {
      issued = await _repository.createInvitation(
        email: email,
        role: role,
        claims: claims,
      );
      if (!_disposed) await loadInvitations();
    });
    return saved ? issued : null;
  }

  Future<bool> revoke(Invitation invitation) async {
    if (!await _waitForBackgroundReads() ||
        !identity.allows(IdentityPermission.manageUsers) ||
        _invitationError != null) {
      return false;
    }
    final current = _invitations
        .where((value) => value.id == invitation.id)
        .firstOrNull;
    if (current == null || current.status != InvitationStatus.pending) {
      return false;
    }
    return _save(() async {
      await _repository.revokeInvitation(invitation.id);
      if (!_disposed) await loadInvitations();
    });
  }

  void clearSaveError() {
    _saveError = null;
    _publish();
  }

  Future<bool> changePassword(String currentPassword, String newPassword) =>
      _save(() async {
        await _repository.changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
        if (!_disposed) {
          onSessionEnded('Password changed. Sign in with your new password.');
        }
      }, passwordChange: true);

  Future<bool> createMember(
    String email,
    String password,
    AccountRole role,
  ) async {
    if (!await _waitForBackgroundReads() || !_canGrant(role)) {
      return false;
    }
    return _save(() async {
      await _repository.createMember(
        email: email,
        password: password,
        role: role,
      );
      if (!_disposed) await load();
    });
  }

  Future<bool> updateMember(
    AccountMember member,
    AccountRole role,
    bool enabled, [
    Set<String> claims = const {},
  ]) async {
    if (!await _waitForBackgroundReads() || !_canGrant(role)) {
      return false;
    }
    final current = _hasMembersSnapshot
        ? _members.where((value) => value.id == member.id).firstOrNull
        : member;
    if (current == null || current.isOwner) return false;
    return _save(() async {
      final updated = await _repository.updateMember(
        id: member.id,
        role: role,
        enabled: enabled,
        claims: claims,
      );
      if (_disposed) return;
      if (updated.id == identity.userId) {
        onSessionEnded('Your membership changed. Please sign in again.');
      } else {
        _members = List.unmodifiable(
          _members.map((value) => value.id == updated.id ? updated : value),
        );
      }
    });
  }

  bool _canGrant(AccountRole role) =>
      identity.allows(IdentityPermission.manageUsers) &&
      _error == null &&
      (!_hasMembersSnapshot || canAssignRole(role));

  Future<bool> _waitForBackgroundReads() async {
    while (_loading || _loadingInvitations) {
      if (_disposed ||
          _saving ||
          (_loading && !_backgroundLoading) ||
          (_loadingInvitations && !_backgroundLoadingInvitations)) {
        return false;
      }
      await Future.wait([
        if (_loading) _membersReadDone!.future,
        if (_loadingInvitations) _invitationsReadDone!.future,
      ]);
    }
    return !_disposed && !_saving;
  }

  Future<bool> _save(
    Future<void> Function() operation, {
    bool passwordChange = false,
  }) async {
    if (_disposed || _saving) return false;
    _saving = true;
    _saveError = null;
    _publish();
    try {
      await operation();
      return !_disposed;
    } on IdentityFailure catch (failure) {
      if (!_disposed) {
        _saveError =
            passwordChange &&
                failure.kind == IdentityFailureKind.invalidCredentials
            ? 'Your current password is incorrect.'
            : failure.message;
      }
      return false;
    } finally {
      _saving = false;
      _publish();
    }
  }

  void _publish() {
    if (!_disposed && !isClosed) {
      emit(
        AccountState(
          loading: _loading && !_backgroundLoading,
          saving: _saving,
          error: _error,
          saveError: _saveError,
          members: _members,
          total: _total,
          claims: _claims,
          invitations: _invitations,
          invitationTotal: _invitationTotal,
          loadingInvitations:
              _loadingInvitations && !_backgroundLoadingInvitations,
          invitationError: _invitationError,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _refresh.dispose();
    _disposed = true;
    return super.close();
  }
}
