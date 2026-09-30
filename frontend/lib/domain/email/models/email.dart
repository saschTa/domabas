import 'dart:convert';

Uri? emailEndpoint(String value) {
  final endpoint = value.trim();
  try {
    if (endpoint.contains('://')) return Uri.tryParse(endpoint);
    if (!endpoint.startsWith('[') && ':'.allMatches(endpoint).length > 1) {
      return Uri(scheme: 'imaps', host: endpoint);
    }
    return Uri.tryParse('imaps://$endpoint');
  } on FormatException {
    return null;
  }
}

final class EmailCapabilities {
  const EmailCapabilities({
    required this.credentialsAvailable,
    this.unavailableReason,
    this.defaultIntervalMinutes = 15,
    this.minIntervalMinutes = 5,
    this.maxIntervalMinutes = 1440,
    this.defaultMaxAgeDays = 30,
    this.minMaxAgeDays = 1,
    this.maxMaxAgeDays = 3650,
    this.defaultPageSize = 50,
    this.minPageSize = 1,
    this.maxPageSize = 100,
    this.maxProviders = 20,
  });
  final bool credentialsAvailable;
  final String? unavailableReason;
  final int defaultIntervalMinutes, minIntervalMinutes, maxIntervalMinutes;
  final int defaultMaxAgeDays, minMaxAgeDays, maxMaxAgeDays;
  final int defaultPageSize, minPageSize, maxPageSize, maxProviders;
}

final class EmailProvider {
  const EmailProvider({
    required this.id,
    required this.namespaceId,
    required this.label,
    required this.host,
    required this.port,
    required this.mailbox,
    required this.intervalMinutes,
    required this.maxAgeDays,
    required this.pageSize,
    required this.enabled,
    required this.revision,
    required this.sourceGeneration,
    required this.credentialState,
    required this.consentState,
    required this.createdAt,
    required this.updatedAt,
    this.lastAttemptAt,
    this.nextDueAt,
    this.activeRunId,
    this.lastRunStatus,
    this.failureCode,
    this.username,
    this.hasPassword = false,
  });
  final String id, namespaceId, label, host, mailbox;
  final int port,
      intervalMinutes,
      maxAgeDays,
      pageSize,
      revision,
      sourceGeneration;
  final bool enabled, hasPassword;
  final String credentialState, consentState;
  final DateTime createdAt, updatedAt;
  final DateTime? lastAttemptAt, nextDueAt;
  final String? activeRunId, lastRunStatus, failureCode, username;
  bool get canRun =>
      enabled && consentState == 'valid' && credentialState == 'ready';
}

final class EmailProviderDraft {
  const EmailProviderDraft({
    this.label = '',
    this.endpoint = '',
    this.port = 993,
    this.username = '',
    this.password = '',
    this.mailbox = 'INBOX',
    this.intervalMinutes = 15,
    this.maxAgeDays = 30,
    this.pageSize = 50,
    this.enabled = false,
  });
  factory EmailProviderDraft.fromProvider(EmailProvider provider) =>
      EmailProviderDraft(
        label: provider.label,
        endpoint: provider.host,
        port: provider.port,
        username: provider.username ?? '',
        mailbox: provider.mailbox,
        intervalMinutes: provider.intervalMinutes,
        maxAgeDays: provider.maxAgeDays,
        pageSize: provider.pageSize,
        enabled: provider.enabled,
      );
  final String label, endpoint, username, password, mailbox;
  final int port, intervalMinutes, maxAgeDays, pageSize;
  final bool enabled;
  EmailProviderDraft copyWith({
    String? label,
    String? endpoint,
    int? port,
    String? username,
    String? password,
    String? mailbox,
    int? intervalMinutes,
    int? maxAgeDays,
    int? pageSize,
    bool? enabled,
  }) => EmailProviderDraft(
    label: label ?? this.label,
    endpoint: endpoint ?? this.endpoint,
    port: port ?? this.port,
    username: username ?? this.username,
    password: password ?? this.password,
    mailbox: mailbox ?? this.mailbox,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    maxAgeDays: maxAgeDays ?? this.maxAgeDays,
    pageSize: pageSize ?? this.pageSize,
    enabled: enabled ?? this.enabled,
  );
  String? validate(
    EmailCapabilities limits, {
    required bool newProvider,
    bool connectionOnly = false,
  }) {
    if (!connectionOnly && (label.trim().isEmpty || label.runes.length > 100)) {
      return 'Enter an account label of at most 100 characters.';
    }
    final uri = emailEndpoint(endpoint);
    if (uri == null ||
        uri.scheme != 'imaps' ||
        uri.host.isEmpty ||
        uri.host.length > 253 ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != port) ||
        port < 1 ||
        port > 65535) {
      return 'Enter a TLS IMAP host and a valid matching port.';
    }
    if (utf8.encode(username).length > 320 ||
        (newProvider && username.isEmpty)) {
      return 'Enter a username of at most 320 bytes.';
    }
    if (utf8.encode(password).length > 4096 ||
        password.contains('\u0000') ||
        (newProvider && password.isEmpty)) {
      return 'Enter a password or app password.';
    }
    if (mailbox.isEmpty ||
        utf8.encode(mailbox).length > 255 ||
        RegExp(r'[\r\n\x00]').hasMatch(mailbox)) {
      return 'Enter a valid mailbox name.';
    }
    if (!connectionOnly &&
        (intervalMinutes < limits.minIntervalMinutes ||
            intervalMinutes > limits.maxIntervalMinutes)) {
      return 'Polling interval must be ${limits.minIntervalMinutes}–${limits.maxIntervalMinutes} minutes.';
    }
    if (!connectionOnly &&
        (maxAgeDays < limits.minMaxAgeDays ||
            maxAgeDays > limits.maxMaxAgeDays)) {
      return 'Maximum age must be ${limits.minMaxAgeDays}–${limits.maxMaxAgeDays} days.';
    }
    if (!connectionOnly &&
        (pageSize < limits.minPageSize || pageSize > limits.maxPageSize)) {
      return 'Page size must be ${limits.minPageSize}–${limits.maxPageSize} messages.';
    }
    return null;
  }

  bool sameNonsecret(EmailProvider provider) {
    final uri = emailEndpoint(endpoint);
    return label.trim() == provider.label &&
        uri?.host.toLowerCase() == provider.host.toLowerCase() &&
        port == provider.port &&
        mailbox == provider.mailbox &&
        intervalMinutes == provider.intervalMinutes &&
        maxAgeDays == provider.maxAgeDays &&
        pageSize == provider.pageSize &&
        enabled == provider.enabled &&
        (username.isEmpty || username == provider.username);
  }
}

final class EmailRun {
  const EmailRun({
    required this.id,
    required this.providerId,
    required this.namespaceId,
    required this.reason,
    required this.status,
    required this.stage,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.failureCode,
    this.messagesDiscovered = 0,
    this.messagesAccepted = 0,
    this.messagesReused = 0,
    this.messagesSkipped = 0,
    this.messagesFailed = 0,
    this.messagesWithContentFailures = 0,
    this.attachmentsAccepted = 0,
    this.attachmentsReused = 0,
    this.attachmentsSkipped = 0,
    this.attachmentsFailed = 0,
    this.hasMore = false,
  });
  final String id, providerId, namespaceId, reason, status, stage;
  final DateTime createdAt;
  final DateTime? startedAt, finishedAt;
  final String? failureCode;
  final int messagesDiscovered,
      messagesAccepted,
      messagesReused,
      messagesSkipped,
      messagesFailed,
      messagesWithContentFailures,
      attachmentsAccepted,
      attachmentsReused,
      attachmentsSkipped,
      attachmentsFailed;
  final bool hasMore;
  bool get active => status == 'queued' || status == 'running';
}

final class EmailProviderPage {
  EmailProviderPage({required Iterable<EmailProvider> items, this.nextCursor})
    : items = List.unmodifiable(items);
  final List<EmailProvider> items;
  final String? nextCursor;
}

final class EmailRunPage {
  EmailRunPage({
    required Iterable<EmailRun> items,
    Map<String, int>? counts,
    this.nextCursor,
  }) : items = List.unmodifiable(items),
       counts = counts == null ? null : Map.unmodifiable(counts);
  final List<EmailRun> items;
  final String? nextCursor;
  final Map<String, int>? counts;
}

final class EmailConnectionResult {
  const EmailConnectionResult({
    required this.success,
    required this.checkedAt,
    this.failureCode,
  });
  final bool success;
  final DateTime checkedAt;
  final String? failureCode;
}

enum EmailFailureKind {
  invalid,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  unavailable,
  invalidResponse,
  cancelled,
}

final class EmailFailure implements Exception {
  const EmailFailure(this.kind);
  final EmailFailureKind kind;
  bool get uncertain =>
      kind == EmailFailureKind.unavailable ||
      kind == EmailFailureKind.invalidResponse;
  String get message => switch (kind) {
    EmailFailureKind.invalid => 'The email account values are invalid.',
    EmailFailureKind.unauthorized => 'Sign in again to manage email accounts.',
    EmailFailureKind.forbidden =>
      'Your current permissions do not allow this action.',
    EmailFailureKind.notFound =>
      'This email account or run is no longer available.',
    EmailFailureKind.conflict => 'The account changed or an import is already active. Reload before trying again.',
    EmailFailureKind.unavailable => 'The email service is unavailable. Check the outcome before retrying a change.',
    EmailFailureKind.invalidResponse => 'The email service returned an invalid response. Reload to check the outcome.',
    EmailFailureKind.cancelled => 'The request was cancelled.',
  };
}
