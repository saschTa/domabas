abstract interface class SessionStore {
  Future<String?> readToken();
  Future<bool> isSignedOut();
  Future<void> saveToken(String token);
  Future<void> clear();
}
