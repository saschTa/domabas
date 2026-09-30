enum ServerProbeResult { ready, notReady, invalidResponse }

abstract interface class ServerPreferencesSource {
  Future<String?> read();
  Future<void> write(String value);
}

abstract interface class ServerConnectionSource {
  Future<ServerProbeResult> check(String address);
}
