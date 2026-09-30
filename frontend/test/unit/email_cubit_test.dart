import 'dart:async';

import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/presentation/email/cubits/email_provider_editor_cubit.dart';
import 'package:domabas/presentation/email/cubits/email_providers_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_email_repository.dart';

final class DelayedEmailRepository extends FakeEmailRepository {
  Completer<EmailRunPage>? delayedRuns;
  final writes = <EmailProviderDraft>[];
  final renewals = <bool>[];
  bool connectionWorks = true;
  @override
  Future<EmailRunPage> listRuns(
    String? providerId, {
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) async =>
      delayedRuns?.future ??
      super.listRuns(providerId, limit: limit, cursor: cursor, cancel: cancel);
  @override
  Future<EmailProvider> updateProvider(
    EmailProvider provider,
    EmailProviderDraft draft, {
    bool renewConsent = false,
    Future<void>? cancel,
  }) async {
    writes.add(draft);
    renewals.add(renewConsent);
    return super.updateProvider(
      provider,
      draft,
      renewConsent: renewConsent,
      cancel: cancel,
    );
  }

  @override
  Future<EmailConnectionResult> testConnection(
    EmailProviderDraft draft, {
    EmailProvider? provider,
    Future<void>? cancel,
  }) async => EmailConnectionResult(
    success: connectionWorks,
    checkedAt: DateTime.utc(2026),
    failureCode: connectionWorks ? null : 'authentication_failed',
  );
}

void main() {
  test(
    'new accounts default to automatic import only with import authority',
    () async {
      for (final allowed in [false, true]) {
        final cubit = EmailProviderEditorCubit(
          FakeEmailRepository(),
          capabilities: const EmailCapabilities(credentialsAvailable: true),
          canImport: allowed,
        );
        expect(cubit.state.draft.enabled, allowed);
        await cubit.close();
      }
      final cubit = EmailProviderEditorCubit(
        FakeEmailRepository(),
        capabilities: const EmailCapabilities(credentialsAvailable: true),
        provider: emailProvider(
          draft: const EmailProviderDraft(
            label: 'Disabled',
            endpoint: 'imap.example.com',
            enabled: false,
          ),
        ),
      );
      expect(cubit.state.draft.enabled, isFalse);
      await cubit.close();
    },
  );
  test('canonical IPv6, bracketed URLs and explicit matching ports reopen correctly', () {
    const limits = EmailCapabilities(credentialsAvailable: true);
    for (final host in [
      '::1',
      '[::1]',
      'imaps://[::1]:993',
      'imap.example.com',
      'imaps://imap.example.com:993',
    ]) {
      final draft = EmailProviderDraft(
        label: 'Mail',
        endpoint: host,
        username: 'user',
        password: 'fixture',
      );
      expect(draft.validate(limits, newProvider: true), isNull, reason: host);
      final provider = emailProvider(draft: draft);
      expect(draft.sameNonsecret(provider), isTrue, reason: host);
      expect(
        EmailProviderDraft.fromProvider(provider)
            .validate(limits, newProvider: false),
        isNull,
      );
    }
    expect(
      const EmailProviderDraft(
        label: 'Mail',
        endpoint: 'imaps://mail.test:143',
        port: 993,
      ).validate(limits, newProvider: false),
      isNotNull,
    );
  });

  for (final action in ['delete', 'import', 'save']) {
    test('late detail page cannot overwrite a completed $action', () async {
      final repository = DelayedEmailRepository()
        ..providers['provider'] = emailProvider();
      final cubit = EmailProvidersCubit(
        repository,
        allowed: true,
        canImport: true,
      );
      addTearDown(cubit.close);
      await cubit.select('provider');
      final delayed = repository.delayedRuns = Completer<EmailRunPage>();
      final read = cubit.load();
      await Future<void>.delayed(Duration.zero);
      if (action == 'delete') {
        await cubit.deleteProvider();
      } else if (action == 'import') {
        await cubit.importNow();
      } else {
        repository.delayedRuns = null;
        await cubit.saved(emailProvider(id: 'replacement'));
      }
      delayed.complete(
        EmailRunPage(
          items: [
            EmailRun(
              id: 'stale',
              providerId: 'provider',
              namespaceId: 'library',
              reason: 'manual',
              status: 'queued',
              stage: 'queued',
              createdAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      await read;
      expect(cubit.state.runs.any((value) => value.id == 'stale'), isFalse);
      if (action == 'delete') {
        expect(cubit.state.provider, isNull);
        expect(cubit.state.selectedId, isNull);
      } else if (action == 'import') {
        expect(cubit.state.runs.single.id, isNot('stale'));
      } else {
        expect(cubit.state.selectedId, 'replacement');
      }
    });
  }

  test(
    'uncertain renewal readback distinguishes still-required consent',
    () async {
      final provider = emailProvider(consent: 'renewal_required');
      final repository = DelayedEmailRepository()
        ..providers[provider.id] = provider;
      final cubit = EmailProviderEditorCubit(
        repository,
        capabilities: const EmailCapabilities(credentialsAvailable: true),
        provider: provider,
      );
      addTearDown(cubit.close);
      repository.failure = const EmailFailure(EmailFailureKind.unavailable);
      await cubit.save(renewConsent: true);
      expect(cubit.state.uncertain, isTrue);
      repository.failure = null;
      await cubit.reconcile();
      expect(cubit.state.notice, contains('renewal was not confirmed'));
      expect(repository.renewals, [true]);
    },
  );

  test('uncertain secret is erased and only an explicit new replacement can be saved', () async {
    final provider = emailProvider();
    final repository = DelayedEmailRepository()
      ..providers[provider.id] = provider;
    final cubit = EmailProviderEditorCubit(
      repository,
      capabilities: const EmailCapabilities(credentialsAvailable: true),
      provider: provider,
    );
    addTearDown(cubit.close);
    cubit.edit(cubit.state.draft.copyWith(password: 'uncertain-secret'));
    repository.failure = const EmailFailure(EmailFailureKind.unavailable);
    await cubit.save();
    repository.failure = null;
    await cubit.reconcile();
    expect(cubit.state.draft.password, isEmpty);
    expect(cubit.state.secretUncertain, isTrue);
    repository.connectionWorks = false;
    await cubit.testConnection(savedCredentials: true);
    await cubit.save();
    expect(repository.writes.length, 1);
    cubit.edit(cubit.state.draft.copyWith(password: 'new-explicit-secret'));
    await cubit.save();
    expect(repository.writes.map((value) => value.password), [
      'uncertain-secret',
      'new-explicit-secret',
    ]);
    expect(cubit.state.saved, isTrue);
  });
}
