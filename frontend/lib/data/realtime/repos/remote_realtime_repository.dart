import '../../../domain/realtime/interfaces/realtime_repository.dart';
import '../../../domain/realtime/models/realtime.dart';
import '../datasources/realtime_websocket_data_source.dart';

final class RemoteRealtimeRepository implements RealtimeRepository {
  RemoteRealtimeRepository(this._source);
  final RealtimeWebSocketDataSource _source;

  @override
  Stream<RealtimeEvent> get events => _source.events.map(
    (record) => RealtimeEvent(
      RealtimeEventKind.values.byName(record.kind),
      closeCode: record.closeCode,
      topics: record.topics.map(
        (topic) => switch (topic) {
          'processing_configuration' => RealtimeTopic.processingConfiguration,
          'system_users' => RealtimeTopic.systemUsers,
          _ => RealtimeTopic.values.byName(topic),
        },
      ),
    ),
  );

  @override
  Future<void> connect() => _source.connect();
  @override
  void disconnect() => _source.disconnect();
  @override
  void dispose() => _source.dispose();
}
