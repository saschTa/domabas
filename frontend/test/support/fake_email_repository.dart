import 'package:domabas/domain/email/interfaces/email_repository.dart';
import 'package:domabas/domain/email/models/email.dart';

class FakeEmailRepository implements EmailRepository {
  final providers = <String, EmailProvider>{};
  final runs = <String, EmailRun>{};
  bool cancelled = false;
  EmailFailure? failure;
  @override
  void cancelRequests() {
    cancelled = true;
  }

  @override
  Future<EmailCapabilities> capabilities({Future<void>? cancel}) async =>
      const EmailCapabilities(credentialsAvailable: true);
  @override
  Future<EmailProviderPage> listProviders({
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) async => EmailProviderPage(items: providers.values);
  @override
  Future<EmailProvider> getProvider(String id, {Future<void>? cancel}) async {
    if (failure case final error?) throw error;
    return providers[id] ??
        (throw const EmailFailure(EmailFailureKind.notFound));
  }

  @override
  Future<EmailProvider> createProvider(
    String id,
    EmailProviderDraft draft, {
    Future<void>? cancel,
  }) async {
    if (failure case final error?) throw error;
    return providers[id] = emailProvider(id: id, draft: draft);
  }

  @override
  Future<EmailProvider> updateProvider(
    EmailProvider provider,
    EmailProviderDraft draft, {
    bool renewConsent = false,
    Future<void>? cancel,
  }) async {
    if (failure case final error?) throw error;
    return providers[provider.id] = emailProvider(
      id: provider.id,
      draft: draft,
      revision: provider.revision + 1,
      consent: renewConsent ? 'valid' : provider.consentState,
    );
  }

  @override
  Future<void> deleteProvider(
    String id,
    int revision, {
    Future<void>? cancel,
  }) async {
    if (failure case final error?) throw error;
    providers.remove(id);
  }

  @override
  Future<EmailConnectionResult> testConnection(
    EmailProviderDraft draft, {
    EmailProvider? provider,
    Future<void>? cancel,
  }) async {
    if (failure case final error?) throw error;
    return EmailConnectionResult(success: true, checkedAt: DateTime.utc(2026));
  }

  @override
  Future<EmailRunPage> listRuns(
    String? providerId, {
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) async => EmailRunPage(
    counts: {
      for (final run in runs.values)
        run.status: runs.values.where((v) => v.status == run.status).length,
    },
    items: runs.values.where(
      (v) =>
          (!activeOnly || v.active) &&
          (providerId == null || v.providerId == providerId) &&
          (status == null || v.status == status),
    ),
  );
  @override
  Future<EmailRun> startRun(
    String providerId,
    String requestId,
    int revision, {
    Future<void>? cancel,
  }) async {
    if (failure case final error?) throw error;
    return runs[requestId] = EmailRun(
      id: requestId,
      providerId: providerId,
      namespaceId: 'library',
      reason: 'manual',
      status: 'queued',
      stage: 'queued',
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  Future<EmailRun> getRun(String id, {Future<void>? cancel}) async =>
      runs[id] ?? (throw const EmailFailure(EmailFailureKind.notFound));
}

EmailProvider emailProvider({
  String id = 'provider',
  EmailProviderDraft draft = const EmailProviderDraft(
    label: 'Mailbox',
    endpoint: 'imap.example.com',
    username: 'reader',
    enabled: true,
  ),
  int revision = 1,
  String consent = 'valid',
}) => EmailProvider(
  id: id,
  namespaceId: 'library',
  label: draft.label,
  host: emailEndpoint(draft.endpoint)!.host,
  port: draft.port,
  mailbox: draft.mailbox,
  intervalMinutes: draft.intervalMinutes,
  maxAgeDays: draft.maxAgeDays,
  pageSize: draft.pageSize,
  enabled: draft.enabled,
  revision: revision,
  sourceGeneration: 1,
  credentialState: 'ready',
  consentState: consent,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  username: draft.username,
  hasPassword: true,
);
