import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/email/interfaces/email_repository.dart';
import '../../../domain/email/models/email.dart';
import 'email_providers_cubit.dart';

final class EmailProviderEditorState {
  const EmailProviderEditorState({
    required this.draft,
    this.provider,
    this.saving = false,
    this.testing = false,
    this.reconciling = false,
    this.uncertain = false,
    this.secretUncertain = false,
    this.error,
    this.notice,
    this.testResult,
    this.saved = false,
  });
  final EmailProviderDraft draft;
  final EmailProvider? provider;
  final bool saving, testing, reconciling, uncertain, secretUncertain, saved;
  final String? error, notice;
  final EmailConnectionResult? testResult;
  bool get busy => saving || reconciling;
}

final class EmailProviderEditorCubit extends Cubit<EmailProviderEditorState> {
  EmailProviderEditorCubit(
    this.repository, {
    required this.capabilities,
    bool canImport = true,
    EmailProvider? provider,
  }) : _provider = provider,
       id = provider?.id ?? emailRequestId(),
       _draft = provider == null
           ? EmailProviderDraft(
               enabled: canImport,
               intervalMinutes: capabilities.defaultIntervalMinutes,
               maxAgeDays: capabilities.defaultMaxAgeDays,
               pageSize: capabilities.defaultPageSize,
             )
           : EmailProviderDraft.fromProvider(provider),
       super(
         EmailProviderEditorState(
           provider: provider,
           draft: provider == null
               ? EmailProviderDraft(
                   enabled: canImport,
                   intervalMinutes: capabilities.defaultIntervalMinutes,
                   maxAgeDays: capabilities.defaultMaxAgeDays,
                   pageSize: capabilities.defaultPageSize,
                 )
               : EmailProviderDraft.fromProvider(provider),
         ),
       );
  final EmailRepository repository;
  final EmailCapabilities capabilities;
  final String id;
  EmailProvider? _provider;
  EmailProviderDraft _draft;
  final _lifetime = Completer<void>();
  Completer<void>? _testCancel;
  int _testEpoch = 0;
  bool _closing = false,
      _saving = false,
      _testing = false,
      _reconciling = false;
  bool _uncertain = false, _secretUncertain = false, _saved = false;
  bool _pendingRenewal = false;
  String? _error, _notice;
  EmailConnectionResult? _testResult;
  void _publish() {
    if (!_closing) {
      emit(
        EmailProviderEditorState(
          draft: _draft,
          provider: _provider,
          saving: _saving,
          testing: _testing,
          reconciling: _reconciling,
          uncertain: _uncertain,
          secretUncertain: _secretUncertain,
          saved: _saved,
          error: _error,
          notice: _notice,
          testResult: _testResult,
        ),
      );
    }
  }

  void edit(EmailProviderDraft draft) {
    if (_closing || _saving || _reconciling || _uncertain) return;
    if (_secretUncertain &&
        draft.password.isNotEmpty &&
        draft.password != _draft.password) {
      _secretUncertain = false;
    }
    _draft = draft;
    _error = null;
    _notice = null;
    _testResult = null;
    _testEpoch++;
    if (_testCancel case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
    _testing = false;
    _publish();
  }

  Future<void> testConnection({bool savedCredentials = false}) async {
    if (_closing ||
        _saving ||
        _reconciling ||
        _testing ||
        (_uncertain && !savedCredentials)) {
      return;
    }
    final draft = savedCredentials && _provider != null
        ? EmailProviderDraft.fromProvider(_provider!)
        : _draft;
    final validation = draft.validate(
      capabilities,
      newProvider: _provider == null,
      connectionOnly: true,
    );
    if (validation != null) {
      _error = validation;
      _publish();
      return;
    }
    final epoch = ++_testEpoch, cancel = _testCancel = Completer<void>();
    _testing = true;
    _error = null;
    _testResult = null;
    _publish();
    try {
      final result = await repository.testConnection(
        draft,
        provider: _provider,
        cancel: cancel.future,
      );
      if (_closing || epoch != _testEpoch) return;
      _testResult = result;
      if (savedCredentials && result.success) {
        _secretUncertain = false;
        _notice = 'Saved credentials connected successfully.';
      }
    } on EmailFailure catch (failure) {
      if (!_closing &&
          epoch == _testEpoch &&
          failure.kind != EmailFailureKind.cancelled) {
        _error = failure.message;
      }
    } finally {
      if (!_closing && epoch == _testEpoch) {
        _testing = false;
        _publish();
      }
    }
  }

  Future<void> save({bool renewConsent = false}) async {
    if (_closing ||
        _saving ||
        _reconciling ||
        _uncertain ||
        _secretUncertain ||
        !capabilities.credentialsAvailable) {
      return;
    }
    final validation = _draft.validate(
      capabilities,
      newProvider: _provider == null,
    );
    if (validation != null) {
      _error = validation;
      _publish();
      return;
    }
    _saving = true;
    _pendingRenewal = renewConsent;
    _testEpoch++;
    if (_testCancel case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
    _testing = false;
    _error = null;
    _publish();
    try {
      final provider = _provider;
      final result = provider == null
          ? await repository.createProvider(
              id,
              _draft,
              cancel: _lifetime.future,
            )
          : await repository.updateProvider(
              provider,
              _draft,
              renewConsent: renewConsent,
              cancel: _lifetime.future,
            );
      if (_closing) return;
      _provider = result;
      _draft = EmailProviderDraft.fromProvider(result);
      _saved = true;
      _pendingRenewal = false;
      _notice = 'Email account saved.';
    } on EmailFailure catch (failure) {
      if (_closing) return;
      _uncertain =
          failure.uncertain || failure.kind == EmailFailureKind.conflict;
      _secretUncertain = failure.uncertain && _draft.password.isNotEmpty;
      _error = failure.message;
    } finally {
      if (!_closing) {
        _saving = false;
        _publish();
      }
    }
  }

  Future<void> reconcile() async {
    if (_closing || _saving || _reconciling || !_uncertain) return;
    _reconciling = true;
    _publish();
    try {
      final result = await repository.getProvider(id, cancel: _lifetime.future);
      if (_closing) return;
      final matches = _draft.sameNonsecret(result);
      _provider = result;
      _uncertain = false;
      _draft = _draft.copyWith(password: '');
      _error = null;
      _notice = _secretUncertain
          ? 'The saved account was reloaded. The password change remains unconfirmed; test saved credentials before making another change.'
          : _pendingRenewal && result.consentState != 'valid'
          ? 'Consent renewal was not confirmed. Review the account and explicitly renew consent again.'
          : matches
          ? 'The saved settings match your draft. Review before closing.'
          : 'The account changed. Your draft is preserved; review before saving.';
      _pendingRenewal = false;
    } on EmailFailure catch (failure) {
      if (_closing) return;
      if (failure.kind == EmailFailureKind.notFound && _provider == null) {
        _uncertain = false;
        _secretUncertain = false;
        _error = null;
        _notice = 'The account was not created. Review your draft before saving again.';
      } else {
        _error = failure.message;
      }
    } finally {
      if (!_closing) {
        _reconciling = false;
        _publish();
      }
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    _testEpoch++;
    if (_testCancel case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
    if (!_lifetime.isCompleted) _lifetime.complete();
    _draft = const EmailProviderDraft();
    await super.close();
  }
}
