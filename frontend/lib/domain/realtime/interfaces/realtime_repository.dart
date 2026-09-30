import '../models/realtime.dart';

abstract interface class RealtimeRepository {
  Stream<RealtimeEvent> get events;
  Future<void> connect();
  void disconnect();
  void dispose();
}
