import 'package:domabas/app/processing_job_counts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProcessingJobCountSnapshot source(
    Map<String, int>? counts, {
    bool refreshing = false,
    bool error = false,
  }) => ProcessingJobCountSnapshot(
    counts: counts,
    refreshing: refreshing,
    error: error,
  );

  test(
    'facets sum full server groups and preserve unsupported status zeros',
    () {
      final sources = {
        'document': source({'succeeded': 12000, 'failed': 23}),
        'ai': source({'succeeded': 42, 'skipped': 7}),
        'email': source({'succeeded': 31, 'partial': 6}),
        'paperless': source({'partial': 3}),
      };
      expect(processingJobCount(sources).count, 12112);
      expect(processingJobCount(sources, status: 'partial').count, 9);
      expect(processingJobCount(sources, pipeline: 'ai').count, 49);
      expect(
        processingJobCount(
          sources,
          pipeline: 'document',
          status: 'failed',
        ).count,
        23,
      );
      expect(
        processingJobCount(
          sources,
          pipeline: 'document',
          status: 'partial',
        ).count,
        0,
      );
    },
  );

  test('unknown totals never become zero or poison independent pipelines', () {
    final sources = {
      'document': source({'failed': 12}),
      'email': source(null, error: true),
    };
    expect(processingJobCount(sources), (
      count: null,
      refreshing: false,
      error: true,
    ));
    expect(processingJobCount(sources, pipeline: 'document'), (
      count: 12,
      refreshing: false,
      error: false,
    ));
    expect(processingJobCount({'email': source({})}).count, 0);
    expect(
      processingJobCount({
        'email': source({'failed': 12}, refreshing: true),
      }),
      (count: 12, refreshing: true, error: false),
    );
  });
}
