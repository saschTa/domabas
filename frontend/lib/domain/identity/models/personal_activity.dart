final class PersonalActivityItem {
  const PersonalActivityItem({
    required this.id,
    required this.kind,
    required this.namespaceId,
    required this.namespaceName,
    required this.status,
    required this.createdAt,
    required this.canOpen,
    this.stage,
    this.startedAt,
    this.finishedAt,
    this.documentId,
    this.providerId,
    this.batchId,
    this.title,
    this.failureCode,
  });
  final String id, kind, namespaceId, namespaceName, status;
  final DateTime createdAt;
  final DateTime? startedAt, finishedAt;
  final String? stage, documentId, providerId, batchId, title, failureCode;
  final bool canOpen;
  bool get active => status == 'queued' || status == 'running';
  String get label =>
      title ??
      switch (kind) {
        'email_retrieval' => 'Email retrieval',
        'reindex_batch' => 'Library reindex',
        'document_ai' => 'AI processing',
        _ => 'Document processing',
      };
}

final class PersonalActivity {
  PersonalActivity({
    required Iterable<PersonalActivityItem> active,
    required Iterable<PersonalActivityItem> finished,
    required this.activeTruncated,
    required this.generatedAt,
    this.activeNextCursor,
    this.finishedNextCursor,
  }) : active = List.unmodifiable(active),
       finished = List.unmodifiable(finished);
  final List<PersonalActivityItem> active, finished;
  final bool activeTruncated;
  final String? activeNextCursor, finishedNextCursor;
  final DateTime generatedAt;
}

enum ActivityFailureKind {
  unauthorized,
  forbidden,
  unavailable,
  invalidResponse,
  cancelled,
}

final class ActivityFailure implements Exception {
  const ActivityFailure(this.kind);
  final ActivityFailureKind kind;
  String get message => switch (kind) {
    ActivityFailureKind.unauthorized => 'Sign in again to view your activity.',
    ActivityFailureKind.forbidden =>
      'Your activity is not available with the current permissions.',
    ActivityFailureKind.unavailable => 'Your activity could not be refreshed.',
    ActivityFailureKind.invalidResponse =>
      'The activity response could not be read.',
    ActivityFailureKind.cancelled => 'The activity request was cancelled.',
  };
}
