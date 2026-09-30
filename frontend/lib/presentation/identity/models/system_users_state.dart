import '../../../domain/identity/models/identity.dart';

final class SystemUsersState {
  SystemUsersState({
    this.loading = false,
    this.saving = false,
    this.error,
    Iterable<SystemUser> users = const [],
    this.total = 0,
    this.adminCount,
  }) : users = List.unmodifiable(users);

  final bool loading;
  final bool saving;
  final String? error;
  final List<SystemUser> users;
  final int total;
  final int? adminCount;
}
