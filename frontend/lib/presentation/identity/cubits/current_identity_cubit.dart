import 'package:bloc/bloc.dart';

import '../../../domain/identity/interfaces/identity_repository.dart';
import '../../../domain/identity/models/identity.dart';
import '../../../domain/identity/models/identity_failure.dart';
import '../../../scheduling/automatic_refresh.dart';

final class CurrentIdentityCubit extends Cubit<Identity> {
  CurrentIdentityCubit(
    this._repository,
    Identity identity, {
    required this.onSessionEnded,
  }) : super(identity);

  final IdentityRepository _repository;
  final void Function(String) onSessionEnded;
  bool _failed = false;
  late final _refresh = AutomaticRefresh(
    read: _load,
    busy: () => false,
    interval: () => Duration(seconds: _failed ? 30 : 1),
  );

  void setActive(bool value) => _refresh.setActive(value);
  void invalidate() => _refresh.invalidate();

  Future<void> _load() async {
    try {
      final identity = await _repository.currentIdentity();
      if (isClosed) return;
      _failed = false;
      if (identity.userId != state.userId ||
          identity.accountId != state.accountId ||
          identity.role != state.role ||
          identity.systemRole != state.systemRole ||
          identity.isOwner != state.isOwner ||
          identity.mustChangePassword != state.mustChangePassword ||
          !_equal(identity.permissions, state.permissions) ||
          !_equal(identity.claims, state.claims)) {
        onSessionEnded('Your access changed. Please sign in again.');
        return;
      }
      emit(identity);
    } on IdentityFailure catch (failure) {
      if (isClosed) return;
      _failed = true;
      if (failure.kind == IdentityFailureKind.unauthorized ||
          failure.kind == IdentityFailureKind.forbidden ||
          failure.kind == IdentityFailureKind.passwordChangeRequired) {
        onSessionEnded('Your access changed. Please sign in again.');
      }
    }
  }

  bool _equal(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  Future<void> close() {
    _refresh.dispose();
    return super.close();
  }
}
