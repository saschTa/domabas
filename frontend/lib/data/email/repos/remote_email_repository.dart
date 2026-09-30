import 'dart:async';

import 'email_job_counts_mapper.dart';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/email/interfaces/email_repository.dart';
import '../../../domain/email/models/email.dart';
import '../datasources/email_remote_data_source.dart';

final class RemoteEmailRepository implements EmailRepository {
  RemoteEmailRepository(this._source, {required this.namespaceId});
  final EmailRemoteDataSource _source;
  final String namespaceId;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  @override
  void cancelRequests() => _source.cancelRequests();
  @override
  Future<EmailCapabilities> capabilities({Future<void>? cancel}) =>
      _translate(() async {
        final value = await _source.capabilities(cancel);
        if (value.transport.toString() != 'implicit_tls' ||
            value.minIntervalMinutes < 1 ||
            value.maxIntervalMinutes < value.minIntervalMinutes ||
            value.defaultIntervalMinutes < value.minIntervalMinutes ||
            value.defaultIntervalMinutes > value.maxIntervalMinutes ||
            value.minMaxAgeDays < 1 ||
            value.maxMaxAgeDays < value.minMaxAgeDays ||
            value.defaultMaxAgeDays < value.minMaxAgeDays ||
            value.defaultMaxAgeDays > value.maxMaxAgeDays ||
            value.minPageSize < 1 ||
            value.maxPageSize > 100 ||
            value.maxPageSize < value.minPageSize ||
            value.defaultPageSize < value.minPageSize ||
            value.defaultPageSize > value.maxPageSize ||
            value.maxProviders < 1 ||
            value.maxProviders > 100) {
          throw const FormatException('Invalid email capabilities');
        }
        return EmailCapabilities(
          credentialsAvailable: value.credentialsAvailable,
          unavailableReason: value.unavailableReason?.toString(),
          defaultIntervalMinutes: value.defaultIntervalMinutes,
          minIntervalMinutes: value.minIntervalMinutes,
          maxIntervalMinutes: value.maxIntervalMinutes,
          defaultMaxAgeDays: value.defaultMaxAgeDays,
          minMaxAgeDays: value.minMaxAgeDays,
          maxMaxAgeDays: value.maxMaxAgeDays,
          defaultPageSize: value.defaultPageSize,
          minPageSize: value.minPageSize,
          maxPageSize: value.maxPageSize,
          maxProviders: value.maxProviders,
        );
      });
  @override
  Future<EmailProviderPage> listProviders({
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.providers(limit, cursor, cancel);
    final items = page.items
        .map((v) => _emailProviderMapper(v.toJson()))
        .toList();
    _page(items.map((v) => v.id), limit);
    return EmailProviderPage(
      items: items,
      nextCursor: _cursor(page.nextCursor),
    );
  });
  @override
  Future<EmailProvider> getProvider(String id, {Future<void>? cancel}) =>
      _translate(
        () async => _matchingProvider(await _source.provider(id, cancel), id),
      );
  @override
  Future<EmailProvider> createProvider(
    String id,
    EmailProviderDraft draft, {
    Future<void>? cancel,
  }) => _translate(() async {
    final body = _CreateEmailProviderRequest(id, draft);
    return _matchingProvider(await _source.create(body, cancel), id);
  });
  @override
  Future<EmailProvider> updateProvider(
    EmailProvider provider,
    EmailProviderDraft draft, {
    bool renewConsent = false,
    Future<void>? cancel,
  }) => _translate(() async {
    final body = _UpdateEmailProviderRequest(provider, draft, renewConsent);
    final result = _matchingProvider(
      await _source.update(provider.id, body, cancel),
      provider.id,
    );
    if (result.revision < provider.revision) {
      throw const FormatException('Stale provider response');
    }
    return result;
  });
  @override
  Future<void> deleteProvider(
    String id,
    int revision, {
    Future<void>? cancel,
  }) => _translate(() => _source.delete(id, revision, cancel));
  @override
  Future<EmailConnectionResult> testConnection(
    EmailProviderDraft draft, {
    EmailProvider? provider,
    Future<void>? cancel,
  }) => _translate(() async {
    final value = await _source.test(
      _TestEmailConnectionRequest(draft, provider),
      cancel,
    );
    if (value.success == (value.failureCode != null)) {
      throw const FormatException('Invalid connection result');
    }
    return EmailConnectionResult(
      success: value.success,
      checkedAt: value.checkedAt.toUtc(),
      failureCode: value.failureCode,
    );
  });
  @override
  Future<EmailRunPage> listRuns(
    String? providerId, {
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.runs(
      providerId,
      limit,
      cursor,
      status,
      activeOnly,
      cancel,
    );
    final items = page.items.map(_emailRunMapper).toList();
    _page(items.map((v) => v.id), limit);
    if (providerId != null && items.any((v) => v.providerId != providerId)) {
      throw const FormatException('Run provider mismatch');
    }
    return EmailRunPage(
      counts: emailJobCountsMapper(page.counts),
      items: items,
      nextCursor: _cursor(page.nextCursor),
    );
  });
  @override
  Future<EmailRun> startRun(
    String providerId,
    String requestId,
    int revision, {
    Future<void>? cancel,
  }) => _translate(() async {
    final run = _emailRunMapper(
      await _source.start(
        providerId,
        api.StartEmailRun(requestId: requestId, expectedRevision: revision),
        cancel,
      ),
    );
    if (run.providerId != providerId || run.reason != 'manual') {
      throw const FormatException('Accepted run mismatch');
    }
    return run;
  });
  @override
  Future<EmailRun> getRun(String id, {Future<void>? cancel}) =>
      _translate(() async {
        final run = _emailRunMapper(await _source.run(id, cancel));
        if (run.id != id) throw const FormatException('Run identity mismatch');
        return run;
      });
  EmailProvider _matchingProvider(api.EmailProvider value, String id) {
    final result = _emailProviderMapper(value.toJson());
    if (result.id != id) {
      throw const FormatException('Provider identity mismatch');
    }
    return result;
  }

  EmailProvider _emailProviderMapper(Map<String, Object?> value) {
    final id = value['id'] as String, account = value['namespaceId'] as String;
    if (!_uuid.hasMatch(id) ||
        account != namespaceId ||
        (value['label'] as String).isEmpty ||
        (value['host'] as String).isEmpty ||
        (value['revision'] as int) < 1 ||
        (value['sourceGeneration'] as int) < 1 ||
        (value['port'] as int) < 1 ||
        (value['port'] as int) > 65535 ||
        (value['intervalMinutes'] as int) < 5 ||
        (value['intervalMinutes'] as int) > 1440 ||
        (value['maxAgeDays'] as int) < 1 ||
        (value['maxAgeDays'] as int) > 3650 ||
        (value['pageSize'] as int) < 1 ||
        (value['pageSize'] as int) > 100 ||
        !{
          'ready',
          'missing_key',
          'unavailable',
        }.contains(value['credentialState'].toString()) ||
        !{
          'valid',
          'renewal_required',
          'disabled',
        }.contains(value['consentState'].toString())) {
      throw const FormatException('Invalid provider');
    }
    final activeRun = value['activeRunId'] as String?;
    if (activeRun != null && !_uuid.hasMatch(activeRun)) {
      throw const FormatException('Invalid active run');
    }
    DateTime? time(String field) => value[field] == null
        ? null
        : DateTime.parse(value[field] as String).toUtc();
    return EmailProvider(
      id: id,
      namespaceId: account,
      label: value['label'] as String,
      host: value['host'] as String,
      port: value['port'] as int,
      mailbox: value['mailbox'] as String,
      intervalMinutes: value['intervalMinutes'] as int,
      maxAgeDays: value['maxAgeDays'] as int,
      pageSize: value['pageSize'] as int,
      enabled: value['enabled'] as bool,
      revision: value['revision'] as int,
      sourceGeneration: value['sourceGeneration'] as int,
      credentialState: value['credentialState'].toString(),
      consentState: value['consentState'].toString(),
      createdAt: time('createdAt')!,
      updatedAt: time('updatedAt')!,
      lastAttemptAt: time('lastAttemptAt'),
      nextDueAt: time('nextDueAt'),
      activeRunId: activeRun,
      lastRunStatus: value['lastRunStatus']?.toString(),
      failureCode: value['failureCode'] as String?,
      username: value['username'] as String?,
      hasPassword: value['hasPassword'] as bool? ?? false,
    );
  }

  EmailRun _emailRunMapper(api.EmailRun value) {
    final active = {'queued', 'running'}.contains(value.status.toString());
    if (!_uuid.hasMatch(value.id) ||
        !_uuid.hasMatch(value.providerId) ||
        value.namespaceId != namespaceId ||
        active != (value.finishedAt == null) ||
        [
          value.messagesDiscovered,
          value.messagesAccepted,
          value.messagesReused,
          value.messagesSkipped,
          value.messagesFailed,
          value.messagesWithContentFailures,
          value.attachmentsAccepted,
          value.attachmentsReused,
          value.attachmentsSkipped,
          value.attachmentsFailed,
        ].any((v) => v < 0)) {
      throw const FormatException('Invalid email run');
    }
    return EmailRun(
      id: value.id,
      providerId: value.providerId,
      namespaceId: value.namespaceId,
      reason: value.reason.toString(),
      status: value.status.toString(),
      stage: value.stage.toString(),
      createdAt: value.createdAt.toUtc(),
      startedAt: value.startedAt?.toUtc(),
      finishedAt: value.finishedAt?.toUtc(),
      failureCode: value.failureCode,
      messagesDiscovered: value.messagesDiscovered,
      messagesAccepted: value.messagesAccepted,
      messagesReused: value.messagesReused,
      messagesSkipped: value.messagesSkipped,
      messagesFailed: value.messagesFailed,
      messagesWithContentFailures: value.messagesWithContentFailures,
      attachmentsAccepted: value.attachmentsAccepted,
      attachmentsReused: value.attachmentsReused,
      attachmentsSkipped: value.attachmentsSkipped,
      attachmentsFailed: value.attachmentsFailed,
      hasMore: value.hasMore,
    );
  }

  static String? _cursor(String? value) {
    if (value != null && (value.isEmpty || value.length > 4096)) {
      throw const FormatException('Invalid email cursor');
    }
    return value;
  }

  static void _page(Iterable<String> ids, int limit) {
    final values = ids.toList();
    if (values.length > limit || values.toSet().length != values.length) {
      throw const FormatException('Invalid email page');
    }
  }

  static Future<T> _translate<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on api.ApiException catch (error) {
      throw EmailFailure(switch (error.code) {
        400 || 413 || 415 || 422 => EmailFailureKind.invalid,
        401 => EmailFailureKind.unauthorized,
        403 => EmailFailureKind.forbidden,
        404 => EmailFailureKind.notFound,
        409 => EmailFailureKind.conflict,
        499 => EmailFailureKind.cancelled,
        _ => EmailFailureKind.unavailable,
      });
    } on TimeoutException {
      throw const EmailFailure(EmailFailureKind.unavailable);
    } on http.ClientException {
      throw const EmailFailure(EmailFailureKind.unavailable);
    } on FormatException {
      throw const EmailFailure(EmailFailureKind.invalidResponse);
    } on TypeError {
      throw const EmailFailure(EmailFailureKind.invalidResponse);
    }
  }
}

final class _CreateEmailProviderRequest extends api.CreateEmailProvider {
  _CreateEmailProviderRequest(String id, EmailProviderDraft draft)
    : super(
        id: id,
        label: draft.label.trim(),
        endpoint: draft.endpoint.trim(),
        port: draft.port,
        username: draft.username,
        password: draft.password,
        mailbox: draft.mailbox,
        intervalMinutes: draft.intervalMinutes,
        maxAgeDays: draft.maxAgeDays,
        pageSize: draft.pageSize,
        enabled: draft.enabled,
      );
  @override
  String toString() => 'CreateEmailProvider[redacted]';
}

final class _UpdateEmailProviderRequest extends api.UpdateEmailProvider {
  _UpdateEmailProviderRequest(
    EmailProvider provider,
    EmailProviderDraft draft,
    bool renew,
  ) : super(
        expectedRevision: provider.revision,
        label: draft.label.trim(),
        endpoint: draft.endpoint.trim(),
        port: draft.port,
        mailbox: draft.mailbox,
        intervalMinutes: draft.intervalMinutes,
        maxAgeDays: draft.maxAgeDays,
        pageSize: draft.pageSize,
        enabled: draft.enabled,
        username: draft.username.isEmpty || draft.username == provider.username
            ? null
            : draft.username,
        password: draft.password.isEmpty ? null : draft.password,
        renewConsent: renew,
      );
  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..removeWhere((_, value) => value == null);
  @override
  String toString() => 'UpdateEmailProvider[redacted]';
}

final class _TestEmailConnectionRequest extends api.TestEmailConnection {
  _TestEmailConnectionRequest(EmailProviderDraft draft, EmailProvider? provider)
    : super(
        providerId: provider?.id,
        expectedRevision: provider?.revision,
        endpoint: draft.endpoint.trim(),
        port: draft.port,
        mailbox: draft.mailbox,
        username: draft.username.isEmpty ? null : draft.username,
        password: draft.password.isEmpty ? null : draft.password,
      );
  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..removeWhere((_, value) => value == null);
  @override
  String toString() => 'TestEmailConnection[redacted]';
}
