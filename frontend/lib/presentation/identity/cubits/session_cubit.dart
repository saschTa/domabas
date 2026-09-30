import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/identity/models/identity.dart';
import '../../../domain/identity/models/identity_failure.dart';
import '../../../domain/identity/interfaces/identity_repository.dart';

import '../models/session_state.dart';

export '../models/session_state.dart';

final class SessionCubit extends Cubit<SessionState> {
  SessionCubit(
    this._repository, {
    DateTime Function()? now,
    Timer Function(Duration, void Function())? scheduleTimer,
  }) : _now = now ?? DateTime.now,
       _scheduleTimer = scheduleTimer ?? Timer.new,
       super(const SessionState());

  final AuthRepository _repository;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _scheduleTimer;
  Future<void> _requests = Future.value();
  Future<void> _storage = Future.value();
  Future<void> _forgetting = Future.value();
  Timer? _expiry;
  AuthSession? _session;
  AuthSession? _issuedSession;
  int _generation = 0;
  bool _disposed = false;
  bool _busy = false;
  bool _restoring = false;
  bool _restoreFailed = false;
  bool _forgetFailed = false;
  bool _loggingOut = false;
  String? _error;
  String? _message;

  AuthSession? get session => state.session;
  bool get busy => state.busy;
  bool get restoring => state.restoring;
  bool get restoreFailed => state.restoreFailed;
  bool get forgetFailed => state.forgetFailed;
  String? get error => state.error;
  String? get message => state.message;

  Future<T> _request<T>(Future<T> Function() operation) {
    final result = _requests.then((_) => operation());
    _requests = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _persist(Future<void> Function() operation) {
    final result = _storage.then((_) => operation());
    _storage = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> restore() async {
    if (_disposed || busy || _session != null || _forgetFailed) return;
    final generation = ++_generation;
    _busy = true;
    _restoring = true;
    _restoreFailed = false;
    _error = null;
    _publish();
    try {
      await _storage;
      final session = await _request(_repository.restore);
      if (_active(generation) && session != null) _install(session);
    } on IdentityFailure catch (failure) {
      if (_active(generation)) {
        _restoreFailed = true;
        _error = failure.message;
      }
    } finally {
      if (_active(generation)) {
        _restoring = false;
        _busy = false;
        _publish();
      }
    }
  }

  Future<void> authenticate({
    required String email,
    required String password,
    String? accountName,
  }) async {
    if (_disposed || busy || restoreFailed) return;
    final generation = ++_generation;
    _busy = true;
    _error = null;
    _message = null;
    _publish();
    try {
      final session = await _request(() async {
        if (!_active(generation)) return null;
        final issued = accountName == null
            ? await _repository.login(email: email, password: password)
            : await _repository.register(
                accountName: accountName,
                email: email,
                password: password,
              );
        _issuedSession = issued;
        return issued;
      });
      if (session != null) {
        try {
          await _rememberAndInstall(session, generation);
        } on IdentityFailure {
          if (_active(generation)) {
            _loggingOut = true;
            try {
              await _forget(generation);
              try {
                await _request(() => _repository.revoke(session));
              } on IdentityFailure {
                // Local removal prevents restoration when revocation cannot reach the server.
              }
            } finally {
              _loggingOut = false;
            }
            if (_active(generation) && !_forgetFailed) {
              _error = 'Could not save your sign-in on this device. Check storage access and sign in again.';
            }
          }
        }
      }
    } on IdentityFailure catch (failure) {
      if (_active(generation)) _error = failure.message;
    } finally {
      if (_active(generation)) {
        _busy = false;
        _publish();
      }
    }
  }

  Future<void> _rememberAndInstall(AuthSession session, int generation) async {
    if (!_active(generation)) return;
    final expiry = session.expiresAt;
    if (expiry != null && !expiry.isAfter(_now())) {
      await _persist(_repository.forget);
      if (_active(generation)) _install(session);
      return;
    }
    await _persist(() async {
      if (_active(generation)) await _repository.remember(session);
    });
    if (_active(generation)) _install(session);
  }

  Future<bool> switchAccount(
    IdentityRepository repository,
    String accountId,
  ) async {
    final expected = _session;
    if (_disposed ||
        busy ||
        expected == null ||
        expected.identity.mustChangePassword) {
      return false;
    }
    final generation = ++_generation;
    _busy = true;
    _error = null;
    _publish();
    try {
      final replacement = await _request(() async {
        if (!_active(generation)) return null;
        final issued = await repository.switchAccount(accountId);
        _issuedSession = issued;
        return issued;
      });
      if (!_active(generation) ||
          !identical(_session, expected) ||
          replacement == null) {
        return false;
      }
      if (replacement.identity.userId != expected.identity.userId ||
          replacement.identity.accountId != accountId ||
          replacement.token == expected.token ||
          replacement.expiresAt != expected.expiresAt) {
        endSession(expected, 'Please sign in again to confirm your library.');
        return false;
      }
      try {
        await _rememberAndInstall(replacement, generation);
      } on IdentityFailure {
        if (_active(generation)) {
          endSession(
            expected,
            'Could not save your library selection. Please sign in again.',
          );
        }
        return false;
      }
      return _active(generation) && _session != null;
    } on IdentityFailure catch (failure) {
      if (_active(generation)) _error = failure.message;
      return false;
    } finally {
      if (_active(generation)) {
        _busy = false;
        _publish();
      }
    }
  }

  void _install(AuthSession session) {
    _expiry?.cancel();
    _expiry = null;
    final expiry = session.expiresAt;
    if (expiry != null) {
      final remaining = expiry.difference(_now());
      if (remaining <= Duration.zero) {
        _session = null;
        _message = 'Your session ended. Please sign in again.';
        return;
      }
      _expiry = _scheduleTimer(remaining, () {
        endSession(session, 'Your session ended. Please sign in again.');
      });
    }
    _session = session;
    _issuedSession = session;
  }

  void clearFormError() {
    if (busy) return;
    _error = null;
    _publish();
  }

  void endSession(AuthSession expected, String message) {
    if (_disposed || !identical(_session, expected)) return;
    _expiry?.cancel();
    _expiry = null;
    final generation = ++_generation;
    _session = null;
    _busy = true;
    _error = null;
    _message = message;
    _publish();
    _forgetting = _forget(generation);
    unawaited(_forgetting);
  }

  Future<void> _forget(int generation) async {
    try {
      await _persist(_repository.forget);
      if (_active(generation)) _forgetFailed = false;
    } on IdentityFailure {
      if (_active(generation)) {
        _forgetFailed = true;
        _error =
            'Could not remove the saved sign-in from this device. Try again.';
      }
    } finally {
      if (_active(generation)) {
        _busy = false;
        _publish();
      }
    }
  }

  Future<void> forgetSavedSession() async {
    if (_disposed || busy) return;
    final generation = ++_generation;
    _restoreFailed = false;
    _restoring = false;
    _busy = true;
    _message = 'You have signed out on this device.';
    _publish();
    await _forget(generation);
  }

  Future<void> logout(IdentityRepository repository) async {
    final expected = _session;
    if (_disposed || expected == null || _loggingOut) return;
    _loggingOut = true;
    final revocation = _request(() {
      final issued = _issuedSession;
      return issued != null && issued.token != expected.token
          ? _repository.revoke(issued)
          : repository.logout();
    });
    endSession(expected, 'Signing out…');
    final generation = _generation;
    String message;
    try {
      await revocation;
      message = 'You have signed out.';
    } on IdentityFailure catch (failure) {
      message = failure.kind == IdentityFailureKind.unauthorized
          ? 'You have signed out.'
          : 'Signed out on this device. Server session revocation could not be confirmed.';
    } finally {
      await _forgetting;
      _loggingOut = false;
    }
    if (_active(generation)) {
      _message = message;
      _publish();
    }
  }

  bool _active(int generation) => !_disposed && _generation == generation;

  void _publish() {
    if (!_disposed && !isClosed) {
      emit(
        SessionState(
          session: _session,
          busy: _busy || _loggingOut,
          restoring: _restoring,
          restoreFailed: _restoreFailed || _forgetFailed,
          forgetFailed: _forgetFailed,
          error: _error,
          message: _message,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _disposed = true;
    _expiry?.cancel();
    _generation++;
    return super.close();
  }
}
