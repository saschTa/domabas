enum RealtimeTopic {
  documents,
  processing,
  processingConfiguration,
  email,
  paperless,
  chat,
  activity,
  identity,
  members,
  systemUsers,
}

enum RealtimeEventKind { ready, invalidate, resync, heartbeat, disconnected }

final class RealtimeEvent {
  RealtimeEvent(
    this.kind, {
    Iterable<RealtimeTopic> topics = const [],
    this.closeCode,
  }) : topics = Set.unmodifiable(topics);

  final RealtimeEventKind kind;
  final Set<RealtimeTopic> topics;
  final int? closeCode;
}

enum RealtimeStatus { inactive, connecting, healthy, reconnecting, unavailable }
