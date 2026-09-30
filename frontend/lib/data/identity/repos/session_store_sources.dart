abstract interface class SecureTokenStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String token);
  Future<void> delete(String key);
}

abstract interface class SessionMarkerStorage {
  String? read(String key);
  void write(String key, String value);
  void delete(String key);
}
