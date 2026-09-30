enum DocumentFailureKind {
  unavailable,
  notFound,
  rejected,
  searchRejected,
  searchUnavailable,
  invalidPassword,
  invalidResponse,
  unauthorized,
  forbidden,
  conflict,
  tooLarge,
  cancelled,
}

final class DocumentFailure implements Exception {
  const DocumentFailure(this.kind);
  final DocumentFailureKind kind;
  String get message => switch (kind) {
    DocumentFailureKind.unavailable =>
      'We could not reach your document server. Please try again.',
    DocumentFailureKind.notFound => 'This document could not be found.',
    DocumentFailureKind.invalidPassword =>
      'That PDF password is incorrect. Try again.',
    DocumentFailureKind.rejected =>
      'The document could not be saved. Check the details and try again.',
    DocumentFailureKind.searchRejected => 'The search could not be completed. Check the search criteria and try again.',
    DocumentFailureKind.searchUnavailable =>
      'The server could not complete the search. Please try again.',
    DocumentFailureKind.invalidResponse =>
      'The server returned an unexpected response. Please try again.',
    DocumentFailureKind.unauthorized =>
      'Your session ended. Please sign in again.',
    DocumentFailureKind.forbidden => 'Your role does not allow this action.',
    DocumentFailureKind.conflict =>
      'This document changed. Reload the latest version before saving again.',
    DocumentFailureKind.tooLarge =>
      'This file or text exceeds the supported size.',
    DocumentFailureKind.cancelled => 'The request was cancelled.',
  };
  @override
  String toString() => message;
}
