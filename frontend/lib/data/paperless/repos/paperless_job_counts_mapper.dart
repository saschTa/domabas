import 'package:domabas_api/api.dart' as api;

Map<String, int>? paperlessJobCountsMapper(api.JobStatusCounts? value) {
  if (value == null) return null;
  final result = <String, int>{};
  for (final group in value.groups) {
    final key = group.status;
    if (group.count < 0 || result.containsKey(key)) {
      throw const FormatException('Invalid job totals');
    }
    result[key] = group.count;
  }
  return result;
}
