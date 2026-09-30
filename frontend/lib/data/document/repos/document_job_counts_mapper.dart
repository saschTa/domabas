import 'package:domabas_api/api.dart' as api;

Map<(String, String), int>? documentJobCountsMapper(
  api.DocumentJobCounts? value,
) {
  if (value == null) return null;
  final result = <(String, String), int>{};
  for (final group in value.groups) {
    final key = (group.pipeline.toString(), group.status);
    if (group.count < 0 || result.containsKey(key)) {
      throw const FormatException('Invalid job totals');
    }
    result[key] = group.count;
  }
  return result;
}

Map<String, int>? documentReindexCountsMapper(api.JobStatusCounts? value) {
  if (value == null) return null;
  final result = <String, int>{};
  for (final group in value.groups) {
    if (group.count < 0 || result.containsKey(group.status)) {
      throw const FormatException("Invalid reindex totals");
    }
    result[group.status] = group.count;
  }
  return result;
}
