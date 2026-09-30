import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/identity/models/identity.dart';
import '../../../domain/identity/models/identity_failure.dart';
import '../../../domain/identity/interfaces/identity_repository.dart';

import '../models/libraries_state.dart';

export '../models/libraries_state.dart';

final class LibrariesCubit extends Cubit<LibrariesState> {
  LibrariesCubit(
    this._repository, {
    required this.identity,
    required this.onSwitch,
  }) : super(LibrariesState());
  final IdentityRepository _repository;
  Identity identity;
  void updateDisplay(Identity value) {
    identity = value;
    _publish();
  }

  final Future<String?> Function(String) onSwitch;
  late final _refresh = AutomaticRefresh(
    read: () => load(preserve: true),
    busy: () => _loading || _acting,
    interval: () => Duration(seconds: _error == null ? 1 : 30),
  );
  bool _active = false, _picker = false, _foreground = true;
  void setActive(bool value, {bool foreground = true}) {
    _active = value;
    _foreground = foreground;
    _refresh.setActive(foreground && (value || _picker));
  }

  void setPickerActive(bool value) {
    _picker = value;
    _refresh.setActive(_foreground && (_active || value));
  }

  void invalidate() => _refresh.invalidate();
  bool _disposed = false;
  bool _loading = false;
  bool _backgroundLoading = false;
  bool _hasSnapshot = false;
  Completer<void>? _readDone;
  bool _acting = false;
  String? _error;
  String? _message;
  List<AccountMembership> _accounts = const [];
  int _total = 0;

  bool get loading => state.loading;
  bool get acting => state.acting;
  String? get error => state.error;
  String? get message => state.message;
  List<AccountMembership> get accounts => state.accounts;
  bool get canLoadMore => _accounts.length < _total;

  Future<void> load({bool more = false, bool preserve = false}) async {
    if (_disposed || (preserve && _acting)) return;
    if (_loading) {
      if (preserve || !_backgroundLoading) return;
      _backgroundLoading = false;
      _publish();
      await _readDone!.future;
      if (!more || _disposed || _loading || _acting || _error != null) return;
    }
    _loading = true;
    _backgroundLoading = preserve && _hasSnapshot;
    final readDone = _readDone = Completer<void>();
    if (!_backgroundLoading) _error = null;
    _publish();
    try {
      final target = preserve ? _accounts.length : 0;
      var page = await _repository.listAccounts(
        offset: more ? _accounts.length : 0,
      );
      final items = <AccountMembership>[...page.items];
      while (!_disposed &&
          preserve &&
          items.length < target &&
          items.length < page.total &&
          page.items.isNotEmpty) {
        page = await _repository.listAccounts(offset: items.length);
        items.addAll(page.items);
      }
      if (_disposed) return;
      _accounts = List.unmodifiable(
        {
          for (final item in [if (more) ..._accounts, ...items]) item.id: item,
        }.values,
      );
      _total = page.total;
      _hasSnapshot = true;
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

  Future<bool> accept(String code) async {
    if (!await _waitForBackgroundRead() || _disposed || _acting || _loading) {
      return false;
    }
    _acting = true;
    _error = null;
    _message = null;
    _publish();
    try {
      final membership = await _repository.acceptInvitation(code);
      if (_disposed) return false;
      await load();
      if (_disposed) return false;
      _message =
          'Invitation accepted for ${membership.name}. Your current library has not changed.';
      return true;
    } on IdentityFailure catch (failure) {
      if (!_disposed) {
        _error = failure.kind == IdentityFailureKind.notFound
            ? 'This invitation is unavailable. Check the code, sign-in email and expiry with its sender.'
            : failure.message;
      }
      return false;
    } finally {
      _acting = false;
      _publish();
    }
  }

  Future<void> switchTo(AccountMembership account) async {
    if (!await _waitForBackgroundRead() ||
        _disposed ||
        _acting ||
        _loading ||
        account.id == identity.accountId ||
        (_hasSnapshot && !_accounts.any((value) => value.id == account.id))) {
      return;
    }
    _acting = true;
    _error = null;
    _message = null;
    _publish();
    try {
      final error = await onSwitch(account.id);
      if (!_disposed) _error = error;
    } finally {
      _acting = false;
      _publish();
    }
  }

  Future<bool> _waitForBackgroundRead() async {
    while (_loading) {
      if (_disposed || _acting || !_backgroundLoading) return false;
      await _readDone!.future;
      if (_error != null) return false;
    }
    return !_disposed && !_acting;
  }

  void _publish() {
    if (!_disposed && !isClosed) {
      emit(
        LibrariesState(
          loading: _loading && !_backgroundLoading,
          acting: _acting,
          error: _error,
          message: _message,
          accounts: _accounts,
          total: _total,
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
