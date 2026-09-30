final class RealtimeRecord {
  RealtimeRecord(
    this.kind, {
    Iterable<String> topics = const [],
    this.closeCode,
  }) : topics = List.unmodifiable(topics);

  final String kind;
  final List<String> topics;
  final int? closeCode;
}
