enum ServerFailureKind { storage, unreachable, notReady, invalidResponse }

final class ServerFailure implements Exception {
  const ServerFailure(this.kind);

  final ServerFailureKind kind;

  String get message => switch (kind) {
    ServerFailureKind.storage => 'Could not save or read the server address on this device. Please try again.',
    ServerFailureKind.unreachable => 'Could not reach this server. Check the address, network connection and certificate if using HTTPS.',
    ServerFailureKind.notReady =>
      'The server is reachable but not ready. Please try again shortly.',
    ServerFailureKind.invalidResponse => 'This address did not return a ready Domabas server. Check the address and include any base path.',
  };
}
