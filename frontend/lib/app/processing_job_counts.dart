final class ProcessingJobCountSnapshot {
  const ProcessingJobCountSnapshot({
    required this.counts,
    required this.refreshing,
    required this.error,
  });

  final Map<String, int>? counts;
  final bool refreshing, error;
}

({int? count, bool refreshing, bool error}) processingJobCount(
  Map<String, ProcessingJobCountSnapshot> sources, {
  String pipeline = 'all',
  String? status,
}) {
  final selected = pipeline == 'all' ? sources.values : [?sources[pipeline]];
  int? count = 0;
  for (final source in selected) {
    final counts = source.counts;
    if (counts == null) {
      count = null;
      break;
    }
    count =
        count! +
        (status == null
            ? counts.values.fold(0, (total, value) => total + value)
            : counts[status] ?? 0);
  }
  return (
    count: count,
    refreshing: selected.any((source) => source.refreshing),
    error: selected.any((source) => source.error),
  );
}
