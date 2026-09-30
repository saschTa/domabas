final class PaperlessConnection {
  const PaperlessConnection({required this.serverUrl, required this.token});
  final String serverUrl;
  final String token;

  String? get validationMessage {
    final url = Uri.tryParse(serverUrl);
    if (serverUrl.length > 2048 ||
        url == null ||
        !{'http', 'https'}.contains(url.scheme) ||
        !url.hasAuthority ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        url.port < 1 ||
        url.port > 65535 ||
        RegExp(r'^https?://[^/?#]*:($|/)').hasMatch(serverUrl) ||
        RegExp(r'[\s\\%]').hasMatch(serverUrl) ||
        serverUrl.contains('..') ||
        url.path.contains('//')) {
      return 'Enter a valid Paperless server URL, including http:// or https://, without a username, query or fragment.';
    }
    if (token.isEmpty ||
        token.length > 256 ||
        token.codeUnits.any((ch) => ch < 33 || ch > 126)) {
      return 'Enter your Paperless API token from My Profile.';
    }
    return null;
  }
}

final class PaperlessOptions {
  const PaperlessOptions({required this.pageSize});
  final int pageSize;
}

final class PaperlessOutcome {
  const PaperlessOutcome({
    required this.sourceId,
    required this.title,
    required this.status,
    this.failureCode,
    this.documentId,
  });
  final int sourceId;
  final String title, status;
  final String? failureCode, documentId;
}

final class PaperlessRun {
  String get status => state == 'succeeded' && failed > 0 ? 'partial' : state;

  PaperlessRun({
    required this.id,
    required this.serverUrl,
    required this.state,
    required this.stage,
    required this.discovered,
    required this.imported,
    required this.duplicates,
    required this.failed,
    required this.cancelRequested,
    required this.createdAt,
    required this.updatedAt,
    this.failureCode,
    Iterable<PaperlessOutcome> outcomes = const [],
  }) : outcomes = List.unmodifiable(outcomes);
  final String id, serverUrl, state, stage;
  final int discovered, imported, duplicates, failed;
  final bool cancelRequested;
  final DateTime createdAt, updatedAt;
  final String? failureCode;
  final List<PaperlessOutcome> outcomes;
  bool get active => state == 'queued' || state == 'running';
}

final class PaperlessFailure implements Exception {
  const PaperlessFailure(this.code);
  final String code;
  bool get uncertain => code == 'unavailable';
  String get message => switch (code) {
    'not_configured' || 'credentials_unavailable' => 'Domabas could not read the saved import token. Contact your administrator.',
    'source_unauthorized' =>
      'Paperless rejected the token or its read permissions.',
    'source_not_found' =>
      'The source document or related metadata is no longer accessible.',
    'source_incompatible' =>
      'Paperless returned an unsupported response. API version 9 is required.',
    'source_too_large' => 'This import exceeded the document limit of an older Domabas version. Start a new import.',
    'source_changed' => 'The source list changed during discovery. Avoid editing Paperless and start a new import.',
    'server_not_allowed' =>
      'This address cannot be used as a Paperless server.',
    'invalid_server_url' =>
      'Enter a valid Paperless server URL, including http:// or https://.',
    'source_busy' ||
    'overloaded' => 'Import capacity is busy. Try again later.',
    'source_unavailable' => 'Could not read Paperless. Check the address, certificate and connection.',
    'invalid_metadata' =>
      'Metadata exceeds Domabas limits or contains invalid values.',
    'body_too_large' => 'The original exceeds the 100 MiB file limit.',
    'unsupported_media_type' =>
      'Only PDF, PNG, JPEG and EML originals are supported.',
    'permission_revoked' => 'Background access ended because credentials, membership or permissions changed.',
    'retry_exhausted' => 'The source stayed unavailable after bounded retries. Check the connection and start a new import.',
    'workflow_closed' || 'delivery_expired' => 'The background job could not finish. Start a new import to resume; existing originals are skipped.',
    'unauthorized' ||
    'forbidden' => 'Your session or import permission is no longer available.',
    'conflict' => 'An import is already active, or this request was used with different connection details. Refresh the job list.',
    'invalid_request' => 'Enter a valid server and API token.',
    'cancelled' => 'Request cancelled.',
    _ => 'The request could not be confirmed. Refresh the list or retry the same request.',
  };
}

final class PaperlessRunPage {
  PaperlessRunPage(
    Iterable<PaperlessRun> items, {
    Map<String, int>? counts,
    this.nextCursor,
  }) : items = List.unmodifiable(items),
       counts = counts == null ? null : Map.unmodifiable(counts);
  final List<PaperlessRun> items;
  final String? nextCursor;
  final Map<String, int>? counts;
}

final class PaperlessOutcomePage {
  PaperlessOutcomePage(Iterable<PaperlessOutcome> items, {this.nextCursor})
    : items = List.unmodifiable(items);
  final List<PaperlessOutcome> items;
  final String? nextCursor;
}
