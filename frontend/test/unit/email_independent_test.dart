import 'dart:async';

import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/presentation/email/cubits/email_provider_editor_cubit.dart';
import 'package:domabas/presentation/email/cubits/email_providers_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_email_repository.dart';

final class IndependentEmailRepository extends FakeEmailRepository {
  Completer<EmailConnectionResult>? delayedTest;
  Completer<EmailCapabilities>? delayedCapabilities;
  bool credentialsAvailable = true;
  bool testCancelled = false;
  int capabilityReads = 0;
  final writes = <EmailProviderDraft>[];
  final starts = <({String provider, String request, int revision})>[];

  @override
  Future<EmailCapabilities> capabilities({Future<void>? cancel}) async {
    capabilityReads++;
    return delayedCapabilities?.future ??
        EmailCapabilities(credentialsAvailable: credentialsAvailable);
  }

  @override
  Future<EmailConnectionResult> testConnection(
    EmailProviderDraft draft, {
    EmailProvider? provider,
    Future<void>? cancel,
  }) async {
    unawaited(
      cancel?.then((_) {
        testCancelled = true;
      }),
    );
    return delayedTest?.future ??
        super.testConnection(draft, provider: provider, cancel: cancel);
  }

  @override
  Future<EmailProvider> updateProvider(
    EmailProvider provider,
    EmailProviderDraft draft, {
    bool renewConsent = false,
    Future<void>? cancel,
  }) async {
    writes.add(draft);
    return super.updateProvider(
      provider,
      draft,
      renewConsent: renewConsent,
      cancel: cancel,
    );
  }

  @override
  Future<EmailRun> startRun(
    String providerId,
    String requestId,
    int revision, {
    Future<void>? cancel,
  }) async {
    starts.add((provider: providerId, request: requestId, revision: revision));
    return super.startRun(providerId, requestId, revision, cancel: cancel);
  }
}

void main() {
  test('superseded capability response cannot reenable credentials on a later poll', () async {
    final repository = IndependentEmailRepository()
      ..providers['provider'] = emailProvider();
    final cubit = EmailProvidersCubit(
      repository,
      allowed: true,
      canImport: true,
    );
    addTearDown(cubit.close);
    final obsolete = repository.delayedCapabilities =
        Completer<EmailCapabilities>();
    final oldRead = cubit.load();
    await Future<void>.delayed(Duration.zero);
    repository.delayedCapabilities = null;
    repository.credentialsAvailable = false;
    await cubit.saved(repository.providers['provider']!);
    expect(cubit.state.capabilities?.credentialsAvailable, isFalse);
    obsolete.complete(const EmailCapabilities(credentialsAvailable: true));
    await oldRead;
    await cubit.load(poll: true);
    expect(
      cubit.state.capabilities?.credentialsAvailable,
      isFalse,
      reason: 'An old request must not mutate private state before its epoch check.',
    );
  });

  test('uncertain run retry retains its original request and revision after a newer poll', () async {
    final repository = IndependentEmailRepository()
      ..providers['provider'] = emailProvider();
    final cubit = EmailProvidersCubit(
      repository,
      allowed: true,
      canImport: true,
    );
    addTearDown(cubit.close);
    await cubit.select('provider');
    repository.failure = const EmailFailure(EmailFailureKind.unavailable);
    await cubit.importNow();
    expect(cubit.state.pendingRun, isTrue);
    repository.failure = null;
    repository.providers['provider'] = emailProvider(revision: 2);
    await cubit.load(poll: true);
    expect(cubit.state.provider?.revision, 2);
    await cubit.importNow(retry: true);
    expect(repository.starts, hasLength(2));
    expect(repository.starts[1], repository.starts[0]);
    expect(repository.starts[1].revision, 1);
    expect(cubit.state.pendingRun, isFalse);
    expect(cubit.state.runs, hasLength(1));
  });

  test('late saved-secret test cannot clear uncertainty for a newer password write', () async {
    final provider = emailProvider();
    final repository = IndependentEmailRepository()
      ..providers[provider.id] = provider;
    final cubit = EmailProviderEditorCubit(
      repository,
      capabilities: const EmailCapabilities(credentialsAvailable: true),
      provider: provider,
    );
    addTearDown(cubit.close);
    cubit.edit(cubit.state.draft.copyWith(password: 'first-write'));
    repository.failure = const EmailFailure(EmailFailureKind.unavailable);
    await cubit.save();
    repository.failure = null;
    await cubit.reconcile();
    final obsolete = repository.delayedTest =
        Completer<EmailConnectionResult>();
    final testing = cubit.testConnection(savedCredentials: true);
    await Future<void>.delayed(Duration.zero);
    cubit.edit(cubit.state.draft.copyWith(password: 'second-write'));
    repository.failure = const EmailFailure(EmailFailureKind.unavailable);
    await cubit.save();
    obsolete.complete(
      EmailConnectionResult(success: true, checkedAt: DateTime.utc(2026)),
    );
    await testing;
    expect(cubit.state.secretUncertain, isTrue);
    expect(cubit.state.uncertain, isTrue);
    expect(cubit.state.testResult, isNull);
    repository.failure = null;
    await cubit.reconcile();
    cubit.edit(cubit.state.draft.copyWith(label: 'Only a label edit'));
    await cubit.save();
    expect(repository.writes.map((draft) => draft.password), [
      'first-write',
      'second-write',
    ]);
    expect(cubit.state.secretUncertain, isTrue);
  });

  test('closing editor invalidates a late saved-credential result and cancels transport', () async {
    final provider = emailProvider();
    final repository = IndependentEmailRepository()
      ..providers[provider.id] = provider;
    final pending = repository.delayedTest = Completer<EmailConnectionResult>();
    final cubit = EmailProviderEditorCubit(
      repository,
      capabilities: const EmailCapabilities(credentialsAvailable: true),
      provider: provider,
    );
    final states = <EmailProviderEditorState>[];
    final subscription = cubit.stream.listen(states.add);
    final operation = cubit.testConnection(savedCredentials: true);
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    expect(repository.testCancelled, isTrue);
    final count = states.length;
    pending.complete(
      EmailConnectionResult(success: true, checkedAt: DateTime.utc(2026)),
    );
    await operation;
    expect(states.length, count);
    expect(states.any((state) => state.testResult != null), isFalse);
    await subscription.cancel();
  });
}
