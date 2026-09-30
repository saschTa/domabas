enum IdentityFailureKind {
  invalidCredentials,
  unauthorized,
  forbidden,
  passwordChangeRequired,
  conflict,
  rejected,
  rateLimited,
  unavailable,
  invalidResponse,
  notFound,
}

final class IdentityFailure implements Exception {
  const IdentityFailure(this.kind);

  final IdentityFailureKind kind;

  String get message => switch (kind) {
    IdentityFailureKind.invalidCredentials =>
      'The email or password is incorrect.',
    IdentityFailureKind.unauthorized =>
      'Your session ended. Please sign in again.',
    IdentityFailureKind.forbidden => 'Your role does not allow this action.',
    IdentityFailureKind.passwordChangeRequired =>
      'Change your initial password to continue.',
    IdentityFailureKind.conflict => 'This change conflicts with an existing account, immutable ownership or the last system administrator.',
    IdentityFailureKind.rejected => 'Check your details and try again.',
    IdentityFailureKind.rateLimited =>
      'Too many attempts. Please wait before trying again.',
    IdentityFailureKind.unavailable =>
      'We could not reach the server. Please try again.',
    IdentityFailureKind.invalidResponse =>
      'The server returned an unexpected response. Please try again.',
    IdentityFailureKind.notFound =>
      'This item is unavailable or you no longer have access.',
  };

  @override
  String toString() => message;
}
