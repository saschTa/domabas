import '../../../domain/identity/models/identity.dart';

final class SessionState {
  const SessionState({
    this.session,
    this.busy = false,
    this.restoring = false,
    this.restoreFailed = false,
    this.forgetFailed = false,
    this.error,
    this.message,
  });

  final AuthSession? session;
  final bool busy;
  final bool restoring;
  final bool restoreFailed;
  final bool forgetFailed;
  final String? error;
  final String? message;
}
