import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/identity/models/identity.dart';
import '../../../domain/identity/models/identity_failure.dart';
import '../../../domain/identity/interfaces/identity_repository.dart';

import '../models/system_users_state.dart';

export '../models/system_users_state.dart';

final class SystemUsersCubit extends Cubit<SystemUsersState> {
  SystemUsersCubit(
    this._repository, {
    required this.identity,
    required this.onSessionEnded,
  }) : super(SystemUsersState());
  final IdentityRepository _repository;
  final Identity identity;
  final void Function(String) onSessionEnded;
  late final _refresh = AutomaticRefresh(
    read: () => load(preserve: true),
    busy: () => _loading || _saving,
    interval: () => Duration(seconds: _error == null ? 1 : 30),
  );
  void setActive(bool value) => _refresh.setActive(value);
  void invalidate() => _refresh.invalidate();
  bool _disposed = false;
  bool _loading = false;
  bool _backgroundLoading = false;
  bool _hasSnapshot = false;
  bool _readFailed = false;
  Completer<void>? _readDone;
  bool _saving = false;
  String? _error;
  List<SystemUser> _users = const [];
  int _total = 0;
  int? _adminCount;
  bool get loading => state.loading;
  bool get saving => state.saving;
  String? get error => state.error;
  List<SystemUser> get users => state.users;
  bool get canLoadMore => _users.length < _total;
  int? get adminCount => state.adminCount;

  bool isLastAdministrator(SystemUser user) =>
      user.role == SystemRole.admin && _adminCount == 1;

  bool canChangeRole(SystemUser user, SystemRole role) =>
      !_disposed &&
      !loading &&
      !_saving &&
      !_readFailed &&
      _adminCount != null &&
      identity.allows(IdentityPermission.manageSystemUsers) &&
      role != user.role &&
      !(role == SystemRole.user && isLastAdministrator(user));

  Future<void> load({bool more = false, bool preserve = false}) async {
    if (_disposed || _saving) return;
    if (_loading) {
      if (preserve || !_backgroundLoading) return;
      _backgroundLoading = false;
      _publish();
      await _readDone!.future;
      if (!more || _disposed || _loading || _saving || _readFailed) return;
    }
    await _load(more: more, preserve: preserve);
  }

  Future<void> _load({
    bool more = false,
    bool clearError = true,
    bool preserve = false,
  }) async {
    _loading = true;
    _backgroundLoading = preserve && _hasSnapshot;
    final readDone = _readDone = Completer<void>();
    if (!_backgroundLoading && clearError) _error = null;
    _publish();
    try {
      final target = preserve ? _users.length : 0;
      var page = await _repository.listSystemUsers(
        offset: more ? _users.length : 0,
      );
      final items = <SystemUser>[...page.items];
      while (!_disposed &&
          preserve &&
          items.length < target &&
          items.length < page.total &&
          page.items.isNotEmpty) {
        page = await _repository.listSystemUsers(offset: items.length);
        items.addAll(page.items);
      }
      if (_disposed) return;
      _users = List.unmodifiable(
        {
          for (final item in [if (more) ..._users, ...items]) item.id: item,
        }.values,
      );
      _total = page.total;
      _adminCount = page.adminCount;
      _hasSnapshot = true;
      _readFailed = false;
      if (clearError) _error = null;
    } on IdentityFailure catch (failure) {
      _readFailed = true;
      if (!_disposed && (clearError || _error == null)) {
        _error = failure.message;
      }
    } finally {
      _loading = false;
      _backgroundLoading = false;
      _publish();
      readDone.complete();
    }
  }

  Future<void> update(SystemUser user, SystemRole role) async {
    while (_loading) {
      if (_disposed || _saving || !_backgroundLoading) return;
      await _readDone!.future;
    }
    final current = _users.where((value) => value.id == user.id).firstOrNull;
    if (current == null) return;
    user = current;
    if (!canChangeRole(user, role)) return;
    _saving = true;
    _error = null;
    _publish();
    try {
      final updated = await _repository.updateSystemUser(user.id, role);
      if (_disposed) return;
      if (updated.id == identity.userId) {
        _adminCount = null;
        onSessionEnded('Your system role changed. Please sign in again.');
      } else {
        _users = List.unmodifiable(
          _users.map((value) => value.id == updated.id ? updated : value),
        );
        await _load();
      }
    } on IdentityFailure catch (failure) {
      if (!_disposed) {
        _error = failure.kind == IdentityFailureKind.conflict
            ? 'At least one system administrator must remain. Promote another user before removing the last administrator.'
            : failure.message;
        if (failure.kind == IdentityFailureKind.conflict) {
          await _load(clearError: false);
        }
      }
    } finally {
      _saving = false;
      _publish();
    }
  }

  void _publish() {
    if (!_disposed && !isClosed) {
      emit(
        SystemUsersState(
          loading: _loading && !_backgroundLoading,
          saving: _saving,
          error: _error,
          users: _users,
          total: _total,
          adminCount: _adminCount,
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
