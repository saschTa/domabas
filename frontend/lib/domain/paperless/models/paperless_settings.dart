final class PaperlessSettings {
  const PaperlessSettings({
    required this.retrievalConcurrency,
    required this.revision,
    required this.minimumRetrievalConcurrency,
    required this.maximumRetrievalConcurrency,
  });

  final int retrievalConcurrency;
  final int revision;
  final int minimumRetrievalConcurrency;
  final int maximumRetrievalConcurrency;
}

final class PaperlessSettingsFailure implements Exception {
  const PaperlessSettingsFailure(this.code);

  final String code;

  String get message => switch (code) {
    'unauthorized' => 'Sign in again to manage Paperless settings.',
    'forbidden' =>
      'System administrator access is required to manage Paperless settings.',
    'conflict' => 'Another administrator changed these settings. Refresh to review the saved value before saving your choice.',
    'invalid_request' => 'Choose a valid number of parallel retrievals.',
    'cancelled' => 'Request cancelled.',
    _ =>
      'Paperless settings could not be confirmed. Refresh before trying again.',
  };
}
