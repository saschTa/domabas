import '../models/server_address.dart';

abstract interface class ServerRepository {
  Future<ServerAddress?> read();
  Future<void> check(ServerAddress address);
  Future<void> save(ServerAddress address);
}
