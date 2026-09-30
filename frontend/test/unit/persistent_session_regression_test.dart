import 'dart:async';

import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas/presentation/identity/cubits/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_identity_repository.dart';

void main() {
  test(
    'logout during an in-flight switch revokes the newly issued bearer',
    () async {
      final auth = FakeAuthRepository();
      final model = SessionCubit(auth);
      addTearDown(model.close);
      await model.authenticate(email: 'a@example.com', password: 'password');
      final switched = Completer<AuthSession>();
      final started = Completer<void>();
      var oldRevocations = 0;
      final identity = FakeIdentityRepository()
        ..onSwitch = (_) {
          started.complete();
          return switched.future;
        }
        ..onLogout = () async {
          oldRevocations++;
        };
      final switching = model.switchAccount(identity, 'account-b');
      await started.future;
      final loggingOut = model.logout(identity);
      expect(model.session, isNull);
      final replacement = testSession(suffix: 'b');
      switched.complete(replacement);
      expect(await switching, isFalse);
      await loggingOut;
      expect(auth.revoked.single.token, replacement.token);
      expect(oldRevocations, 0);
      expect(auth.saved, isNull);
    },
  );

  test(
    'failed sign-in storage is cleared even when the write completed late',
    () async {
      final auth = FakeAuthRepository();
      auth.onRemember = (session) async {
        auth.saved = session;
        throw const IdentityFailure(IdentityFailureKind.unavailable);
      };
      final model = SessionCubit(auth);
      addTearDown(model.close);
      await model.authenticate(email: 'a@example.com', password: 'password');
      expect(model.error, contains('storage access'));
      expect(auth.saved, isNull);
      expect(auth.revoked.single.token, auth.next.token);
      final reopened = SessionCubit(auth);
      addTearDown(reopened.close);
      await reopened.restore();
      expect(reopened.session, isNull);
    },
  );
}
