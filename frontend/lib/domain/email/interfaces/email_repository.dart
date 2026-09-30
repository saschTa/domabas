import '../models/email.dart';

abstract interface class EmailRepository {
  void cancelRequests();
  Future<EmailCapabilities> capabilities({Future<void>? cancel});
  Future<EmailProviderPage> listProviders({
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  });
  Future<EmailProvider> getProvider(String id, {Future<void>? cancel});
  Future<EmailProvider> createProvider(
    String id,
    EmailProviderDraft draft, {
    Future<void>? cancel,
  });
  Future<EmailProvider> updateProvider(
    EmailProvider provider,
    EmailProviderDraft draft, {
    bool renewConsent = false,
    Future<void>? cancel,
  });
  Future<void> deleteProvider(String id, int revision, {Future<void>? cancel});
  Future<EmailConnectionResult> testConnection(
    EmailProviderDraft draft, {
    EmailProvider? provider,
    Future<void>? cancel,
  });
  Future<EmailRunPage> listRuns(
    String? providerId, {
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  });
  Future<EmailRun> startRun(
    String providerId,
    String requestId,
    int revision, {
    Future<void>? cancel,
  });
  Future<EmailRun> getRun(String id, {Future<void>? cancel});
}
