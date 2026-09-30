import '../../../domain/server/interfaces/server_repository.dart';
import '../../../domain/server/models/server_address.dart';
import '../../../domain/server/models/server_failure.dart';
import 'server_sources.dart';

final class LocalServerRepository implements ServerRepository {
  LocalServerRepository(this._preferences, this._connection);

  final ServerPreferencesSource _preferences;
  final ServerConnectionSource _connection;

  @override
  Future<ServerAddress?> read() async {
    try {
      final value = await _preferences.read();
      return value == null ? null : ServerAddress.parse(value);
    } catch (_) {
      throw const ServerFailure(ServerFailureKind.storage);
    }
  }

  @override
  Future<void> save(ServerAddress address) async {
    try {
      await _preferences.write(address.value);
      if (await _preferences.read() != address.value) {
        throw const ServerFailure(ServerFailureKind.storage);
      }
    } catch (_) {
      throw const ServerFailure(ServerFailureKind.storage);
    }
  }

  @override
  Future<void> check(ServerAddress address) async {
    final ServerProbeResult result;
    try {
      result = await _connection.check(address.value);
    } catch (_) {
      throw const ServerFailure(ServerFailureKind.unreachable);
    }
    switch (result) {
      case ServerProbeResult.ready:
        return;
      case ServerProbeResult.notReady:
        throw const ServerFailure(ServerFailureKind.notReady);
      case ServerProbeResult.invalidResponse:
        throw const ServerFailure(ServerFailureKind.invalidResponse);
    }
  }
}
