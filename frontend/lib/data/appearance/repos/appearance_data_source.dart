abstract interface class AppearanceDataSource {
  Future<String?> read();
  Future<void> write(String value);
}
