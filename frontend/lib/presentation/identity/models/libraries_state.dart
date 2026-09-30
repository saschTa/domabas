import '../../../domain/identity/models/identity.dart';

final class LibrariesState {
  LibrariesState({
    this.loading = false,
    this.acting = false,
    this.error,
    this.message,
    Iterable<AccountMembership> accounts = const [],
    this.total = 0,
  }) : accounts = List.unmodifiable(accounts);

  final bool loading;
  final bool acting;
  final String? error;
  final String? message;
  final List<AccountMembership> accounts;
  final int total;
}
