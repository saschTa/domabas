import 'package:domabas/domain/server/interfaces/server_repository.dart';
import 'package:domabas/domain/server/models/server_address.dart';

final class FakeServerRepository implements ServerRepository {
  ServerAddress? stored;
  Future<ServerAddress?> Function()? onRead;
  Future<void> Function(ServerAddress)? onCheck;
  Future<void> Function(ServerAddress)? onSave;
  final checks = <ServerAddress>[];
  final saves = <ServerAddress>[];

  @override
  Future<ServerAddress?> read() async =>
      onRead == null ? stored : await onRead!();

  @override
  Future<void> check(ServerAddress address) async {
    checks.add(address);
    await onCheck?.call(address);
  }

  @override
  Future<void> save(ServerAddress address) async {
    saves.add(address);
    await onSave?.call(address);
    stored = address;
  }
}
