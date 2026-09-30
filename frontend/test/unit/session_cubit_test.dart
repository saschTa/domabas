import 'dart:async';

import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas/presentation/identity/cubits/account_cubit.dart';
import 'package:domabas/presentation/identity/cubits/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_identity_repository.dart';

void main() {
  test('idle expiry clears only its own session and already expired responses stay signed out', () async {
    final now = DateTime.utc(2026, 9, 17);
    final repository = FakeAuthRepository();
    final timers = <_ControlledTimer>[];
    final model = SessionCubit(
      repository,
      now: () => now,
      scheduleTimer: (duration, callback) {
        expect(duration, isPositiveDuration);
        final timer = _ControlledTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(model.close);
    final expired = AuthSession(
      token: 'expired',
      expiresAt: now,
      identity: repository.next.identity,
    );
    repository.next = expired;
    await model.authenticate(email: 'a@example.com', password: 'password');
    expect(model.session, isNull);
    expect(timers, isEmpty);

    repository.next = testSession();
    await model.authenticate(email: 'a@example.com', password: 'password');
    final oldTimer = timers.single;
    repository.next = testSession(suffix: 'b');
    await model.authenticate(email: 'b@example.com', password: 'password');
    expect(oldTimer.isActive, isFalse);
    oldTimer.fireEvenIfCancelled();
    expect(model.session, same(repository.next));
    timers.last.fireEvenIfCancelled();
    expect(model.session, isNull);
    expect(model.message, contains('session ended'));
    expect(timers.last.isActive, isFalse);
  });

  test('pending authentication blocks another request and old 401 cannot clear a newer session', () async {
    final old = Completer<AuthSession>();
    final started = Completer<void>();
    final repository = FakeAuthRepository()
      ..onLogin = () {
        started.complete();
        return old.future;
      };
    final model = SessionCubit(repository);
    addTearDown(model.close);
    final request = model.authenticate(
      email: 'a@example.com',
      password: 'password',
    );
    final current = testSession(suffix: 'b');
    await started.future;
    repository.onLogin = () async => current;
    await model.authenticate(email: 'b@example.com', password: 'password');
    expect(model.session, isNull);
    old.complete(testSession());
    await request;
    final previous = model.session!;
    await model.authenticate(email: 'b@example.com', password: 'password');
    expect(model.session, same(current));
    model.endSession(previous, 'old 401');
    expect(model.session, same(current));
  });

  test('logout clears immediately and blocks login until cookie revocation finishes', () async {
    final logout = Completer<void>();
    final identity = FakeIdentityRepository()..onLogout = () => logout.future;
    final repository = FakeAuthRepository();
    final model = SessionCubit(repository);
    addTearDown(model.close);
    await model.authenticate(email: 'a@example.com', password: 'password');
    final pending = model.logout(identity);
    expect(model.session, isNull);
    logout.completeError(
      const IdentityFailure(IdentityFailureKind.unavailable),
    );
    await pending;
    expect(model.message, contains('could not be confirmed'));

    await model.authenticate(email: 'a@example.com', password: 'password');
    final later = Completer<void>();
    identity.onLogout = () => later.future;
    final oldLogout = model.logout(identity);
    repository.next = testSession(suffix: 'b');
    await model.authenticate(email: 'b@example.com', password: 'password');
    expect(model.session, isNull);
    expect(model.busy, isTrue);
    later.completeError(const IdentityFailure(IdentityFailureKind.unavailable));
    await oldLogout;
    await model.authenticate(email: 'b@example.com', password: 'password');
    expect(model.session, same(repository.next));
    expect(model.message, isNull);
  });

  test('restores authoritative sessions without an expiry timer', () async {
    final repository = FakeAuthRepository();
    final restored = AuthSession(
      token: repository.next.token,
      expiresAt: null,
      identity: repository.next.identity,
    );
    repository.saved = restored;
    final model = SessionCubit(
      repository,
      scheduleTimer: (_, _) => throw StateError('No expiry timer expected'),
    );
    addTearDown(model.close);
    final pending = model.restore();
    expect(model.restoring, isTrue);
    await pending;
    expect(model.session, same(restored));
    expect(model.restoring, isFalse);
    expect(model.restoreFailed, isFalse);
  });

  test('unavailable restoration preserves credentials and can retry', () async {
    final repository = FakeAuthRepository()..saved = testSession();
    repository.onRestore = () async =>
        throw const IdentityFailure(IdentityFailureKind.unavailable);
    final model = SessionCubit(repository);
    addTearDown(model.close);
    await model.restore();
    expect(model.restoreFailed, isTrue);
    expect(model.session, isNull);
    expect(repository.saved, isNotNull);
    repository.onRestore = null;
    await model.restore();
    expect(model.session, same(repository.saved));
    expect(model.restoreFailed, isFalse);
  });

  test('offline logout prevents restoration in a new app instance', () async {
    final repository = FakeAuthRepository();
    final model = SessionCubit(repository);
    addTearDown(model.close);
    await model.authenticate(email: 'a@example.com', password: 'password');
    final identity = FakeIdentityRepository()
      ..onLogout = () async =>
          throw const IdentityFailure(IdentityFailureKind.unavailable);
    await model.logout(identity);
    final reopened = SessionCubit(repository);
    addTearDown(reopened.close);
    await reopened.restore();
    expect(reopened.session, isNull);
    expect(repository.saved, isNull);
  });

  test(
    'failed storage removal blocks restoration until removal is retried',
    () async {
      final repository = FakeAuthRepository()..saved = testSession();
      final model = SessionCubit(repository);
      addTearDown(model.close);
      await model.restore();
      repository.onForget = () async =>
          throw const IdentityFailure(IdentityFailureKind.unavailable);
      await model.logout(FakeIdentityRepository());
      expect(model.session, isNull);
      expect(model.forgetFailed, isTrue);
      expect(model.error, contains('saved sign-in'));
      await model.authenticate(email: 'b@example.com', password: 'password');
      expect(model.session, isNull);
      repository.onForget = null;
      await model.forgetSavedSession();
      expect(repository.saved, isNull);
      expect(model.restoreFailed, isFalse);
    },
  );

  test(
    'logout removes a rotated token even when its storage write was pending',
    () async {
      final repository = FakeAuthRepository();
      final model = SessionCubit(repository);
      addTearDown(model.close);
      await model.authenticate(email: 'a@example.com', password: 'password');
      final saved = Completer<void>();
      final saveStarted = Completer<void>();
      repository.onRemember = (_) {
        saveStarted.complete();
        return saved.future;
      };
      final previous = model.session!;
      final replacement = AuthSession(
        token: 'rotated-token',
        expiresAt: previous.expiresAt,
        identity: testSession(suffix: 'b').identity,
      );
      final identity = FakeIdentityRepository()
        ..onSwitch = (_) async => AuthSession(
          token: replacement.token,
          expiresAt: previous.expiresAt,
          identity: Identity(
            userId: previous.identity.userId,
            email: previous.identity.email,
            accountId: 'account-b',
            accountName: 'B',
            role: AccountRole.viewer,
            mustChangePassword: false,
            permissions: [IdentityPermission.readDocuments],
          ),
        );
      final switching = model.switchAccount(identity, 'account-b');
      await saveStarted.future;
      final logout = model.logout(identity);
      expect(model.session, isNull);
      saved.complete();
      await switching;
      await logout;
      expect(repository.saved, isNull);
      expect(model.session, isNull);
    },
  );

  test(
    'storage failure does not install a login or disposed restoration',
    () async {
      final repository = FakeAuthRepository()
        ..onRemember = (_) async =>
            throw const IdentityFailure(IdentityFailureKind.unavailable);
      final model = SessionCubit(repository);
      await model.authenticate(email: 'a@example.com', password: 'password');
      expect(model.session, isNull);
      expect(model.error, isNotNull);
      final restored = Completer<AuthSession?>();
      repository.onRestore = () => restored.future;
      final pending = model.restore();
      await model.close();
      restored.complete(testSession());
      await pending;
      expect(model.session, isNull);
    },
  );

  test(
    'disposed login and member requests do not publish stale state',
    () async {
      final login = Completer<AuthSession>();
      final repository = FakeAuthRepository()..onLogin = () => login.future;
      final model = SessionCubit(repository);
      var notifications = 0;
      model.stream.listen((_) => notifications++);
      final pending = model.authenticate(
        email: 'a@example.com',
        password: 'password',
      );
      await model.close();
      login.complete(testSession());
      await pending;
      expect(model.session, isNull);
      expect(notifications, 1);

      final list = Completer<MemberPage>();
      final identity = FakeIdentityRepository()..onList = () => list.future;
      final account = AccountCubit(
        identity,
        identity: testSession().identity,
        onSessionEnded: (_) => fail('disposed callback'),
      );
      final loading = account.load();
      await account.close();
      list.complete(MemberPage(items: [], total: 0));
      await loading;
      expect(account.members, isEmpty);
    },
  );

  test(
    'wrong current password keeps session, self membership change ends it',
    () async {
      final repository = FakeIdentityRepository()
        ..changeFailure = const IdentityFailure(
          IdentityFailureKind.invalidCredentials,
        );
      final ended = <String>[];
      final identity = testSession().identity;
      final model = AccountCubit(
        repository,
        identity: identity,
        onSessionEnded: ended.add,
      );
      addTearDown(model.close);
      expect(await model.changePassword('wrong', 'new password here'), isFalse);
      expect(model.saveError, 'Your current password is incorrect.');
      expect(ended, isEmpty);
      final self = AccountMember(
        id: identity.userId,
        email: identity.email,
        role: AccountRole.admin,
        enabled: true,
        mustChangePassword: false,
      );
      repository.members = [self];
      expect(await model.updateMember(self, AccountRole.user, true), isTrue);
      expect(ended.single, contains('membership changed'));
    },
  );

  test(
    'password validation counts Unicode without trimming or normalizing',
    () {
      expect(IdentityCredentials.validatePassword('short'), isNotNull);
      expect(IdentityCredentials.validatePassword('abcdefg'), isNotNull);
      expect(IdentityCredentials.validatePassword('abcdefgh'), isNull);
      expect(IdentityCredentials.validatePassword('😀' * 7), isNotNull);
      expect(IdentityCredentials.validatePassword('😀' * 8), isNull);
      expect(IdentityCredentials.validatePassword('a' * 129), isNotNull);
      expect(IdentityCredentials.validatePassword(' ' * 15), isNull);
      expect(IdentityCredentials.validateEmail(' User@Example.com '), isNull);
      expect(IdentityCredentials.validateEmail('Nämé@example.com'), isNotNull);
      expect(
        IdentityCredentials.validateEmail('User <user@example.com>'),
        isNotNull,
      );
    },
  );
}

final isPositiveDuration = predicate<Duration>(
  (value) => value > Duration.zero,
);

final class _ControlledTimer implements Timer {
  _ControlledTimer(this.callback);

  final void Function() callback;
  bool _active = true;

  void fireEvenIfCancelled() => callback();

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
