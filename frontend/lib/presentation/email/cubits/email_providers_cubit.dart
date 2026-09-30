import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/email/interfaces/email_repository.dart';
import '../../../domain/email/models/email.dart';

String emailRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final class EmailProvidersState {
  EmailProvidersState({
    this.capabilities,
    Iterable<EmailProvider> providers = const [],
    this.selectedId,
    this.provider,
    Iterable<EmailRun> runs = const [],
    this.providerCursor,
    this.runCursor,
    this.loading = false,
    this.saving = false,
    this.error,
    this.notice,
    this.pendingRun = false,
    this.reconcileDelete = false,
    this.browsingHistory = false,
  }) : providers = List.unmodifiable(providers),
       runs = List.unmodifiable(runs);
  final EmailCapabilities? capabilities;
  final List<EmailProvider> providers;
  final String? selectedId, providerCursor, runCursor, error, notice;
  final EmailProvider? provider;
  final List<EmailRun> runs;
  final bool loading, saving, pendingRun, reconcileDelete, browsingHistory;
}

final class EmailProvidersCubit extends Cubit<EmailProvidersState> {
  EmailProvidersCubit(
    this.repository, {
    required this.allowed,
    required this.canImport,
  }) : super(EmailProvidersState());
  final EmailRepository repository;
  final bool allowed, canImport;
  final _lifetime = Completer<void>();
  Completer<void>? _readCancel;
  late final _refresh = AutomaticRefresh(
    read: () => load(poll: true),
    busy: () => _loading || _saving,
    interval: () => Duration(seconds: _error == null ? 1 : 30),
  );
  void invalidate() => _refresh.invalidate();

  bool _active = false,
      _closing = false,
      _loading = false,
      _saving = false,
      _history = false;
  int _readEpoch = 0;
  bool _providerHistory = false;
  bool _polling = false, _providersLoaded = false, _detailLoaded = false;
  bool get _blockingRead =>
      _loading &&
      (!_polling || !(_selectedId == null ? _providersLoaded : _detailLoaded));
  EmailCapabilities? _capabilities;
  List<EmailProvider> _providers = [];
  List<EmailRun> _runs = [];
  EmailProvider? _provider;
  String? _selectedId,
      _providerCursor,
      _runCursor,
      _error,
      _notice,
      _deletePending;
  ({String providerId, String requestId, int revision})? _pending;

  void _publish() {
    if (_closing) return;
    emit(
      EmailProvidersState(
        capabilities: _capabilities,
        providers: _providers,
        selectedId: _selectedId,
        provider: _provider,
        runs: _runs,
        providerCursor: _providerCursor,
        runCursor: _runCursor,
        loading: _blockingRead,
        saving: _saving,
        error: _error,
        notice: _notice,
        pendingRun: _pending != null,
        reconcileDelete: _deletePending != null,
        browsingHistory: _history,
      ),
    );
  }

  void _cancelRead() {
    if (_loading && !_blockingRead) _refresh.invalidate();
    _readEpoch++;
    if (_readCancel case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
    _loading = false;
  }

  void setActive(bool value) {
    if (_closing || !allowed) return;
    if (_active == value) return;
    _active = value;
    _refresh.setActive(value);
    if (value) {
      unawaited(load(poll: true));
    } else {
      _readEpoch++;
      if (_readCancel case final cancel? when !cancel.isCompleted) {
        cancel.complete();
      }
      _loading = false;
      _publish();
    }
  }

  Future<void> select(String id) async {
    if (_closing ||
        !allowed ||
        _saving ||
        _pending != null ||
        _deletePending != null) {
      return;
    }
    _readEpoch++;
    if (_readCancel case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
    _loading = false;
    _selectedId = id;
    _detailLoaded = false;
    _provider = null;
    _runs = [];
    _runCursor = null;
    _history = false;
    _error = null;
    _notice = null;
    _publish();
    await load();
  }

  Future<void> back() async {
    if (_saving || _pending != null || _deletePending != null || _closing) {
      return;
    }
    _readEpoch++;
    if (_readCancel case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
    _loading = false;
    _selectedId = null;
    _provider = null;
    _runs = [];
    _history = false;
    _notice = null;
    await load(poll: true);
  }

  Future<void> load({bool poll = false, bool more = false}) async {
    if (!poll && _loading && !_blockingRead) _cancelRead();
    if (_closing ||
        !allowed ||
        _loading ||
        _saving ||
        (more &&
            (_selectedId == null ? _providerCursor : _runCursor) == null)) {
      return;
    }
    final epoch = ++_readEpoch, selected = _selectedId;
    final cancel = _readCancel = Completer<void>();
    _loading = true;
    _polling = poll;
    if (!poll) _error = null;
    _publish();
    try {
      if (_capabilities == null || !poll) {
        final capabilities = await repository.capabilities(
          cancel: cancel.future,
        );
        if (_closing || epoch != _readEpoch) return;
        _capabilities = capabilities;
      }
      if (_closing || epoch != _readEpoch) return;
      if (selected == null) {
        final page = await repository.listProviders(
          cursor: more ? _providerCursor : null,
          cancel: cancel.future,
        );
        if (_closing || epoch != _readEpoch) return;
        if (poll && _providerHistory) {
          final updates = {
            for (final provider in page.items) provider.id: provider,
          };
          final older = _providers
              .where((provider) => !updates.containsKey(provider.id))
              .toList();
          final removed = <String>{};
          for (final provider in older) {
            try {
              updates[provider.id] = await repository.getProvider(
                provider.id,
                cancel: cancel.future,
              );
            } on EmailFailure catch (failure) {
              if (failure.kind == EmailFailureKind.notFound) {
                removed.add(provider.id);
              } else {
                rethrow;
              }
            }
            if (_closing || epoch != _readEpoch) return;
          }
          _providers = _providers
              .where((provider) => !removed.contains(provider.id))
              .map((provider) => updates[provider.id] ?? provider)
              .toList();
        } else {
          _providers = more
              ? [
                  ..._providers,
                  ...page.items.where(
                    (v) => !_providers.any((p) => p.id == v.id),
                  ),
                ]
              : page.items;
          _providerCursor = page.nextCursor;
          _providerHistory = more;
        }
        _providersLoaded = true;
      } else {
        final provider = await repository.getProvider(
          selected,
          cancel: cancel.future,
        );
        if (_closing || epoch != _readEpoch) return;
        _provider = provider;
        if (poll && _history) {
          final updates = <String, EmailRun>{};
          final active = _runs.where((run) => run.active).toList();
          for (final run in active) {
            updates[run.id] = await repository.getRun(
              run.id,
              cancel: cancel.future,
            );
            if (_closing || epoch != _readEpoch) return;
          }
          _runs = _runs.map((run) => updates[run.id] ?? run).toList();
        } else {
          final page = await repository.listRuns(
            selected,
            cursor: more ? _runCursor : null,
            cancel: cancel.future,
          );
          if (_closing || epoch != _readEpoch) return;
          _runs = more
              ? [
                  ..._runs,
                  ...page.items.where((v) => !_runs.any((r) => r.id == v.id)),
                ]
              : page.items;
          _runCursor = page.nextCursor;
          _history = more;
        }
        _detailLoaded = true;
      }
      _error = null;
    } on EmailFailure catch (failure) {
      if (!_closing &&
          epoch == _readEpoch &&
          failure.kind != EmailFailureKind.cancelled) {
        _error = failure.message;
      }
    } finally {
      if (!_closing && epoch == _readEpoch) {
        _loading = false;
        _publish();
      }
    }
  }

  Future<void> saved(EmailProvider provider) async {
    if (_closing) return;
    _cancelRead();
    _provider = provider;
    _selectedId = provider.id;
    _detailLoaded = false;
    _notice = 'Email account saved.';
    _error = null;
    _history = false;
    _publish();
    await load();
  }

  Future<void> importNow({bool retry = false}) async {
    final provider = _provider;
    if (_closing ||
        _saving ||
        !allowed ||
        !canImport ||
        provider == null ||
        _deletePending != null) {
      return;
    }
    if (!retry && (_pending != null || !provider.canRun)) return;
    if (retry && _pending == null) return;
    _cancelRead();
    final pending = _pending ??= (
      providerId: provider.id,
      requestId: emailRequestId(),
      revision: provider.revision,
    );
    _saving = true;
    _error = null;
    _notice = null;
    _publish();
    try {
      final run = await repository.startRun(
        pending.providerId,
        pending.requestId,
        pending.revision,
        cancel: _lifetime.future,
      );
      if (_closing) return;
      _pending = null;
      _runs = [run, ..._runs.where((r) => r.id != run.id)];
      _notice = 'Import accepted. Document processing continues separately.';
    } on EmailFailure catch (failure) {
      if (_closing) return;
      if (!failure.uncertain) _pending = null;
      _error = failure.message;
    } finally {
      if (!_closing) {
        _saving = false;
        _publish();
      }
    }
  }

  Future<void> deleteProvider() async {
    final provider = _provider;
    if (_closing || _saving || provider == null || _pending != null) return;
    _cancelRead();
    _saving = true;
    _error = null;
    _publish();
    try {
      await repository.deleteProvider(
        provider.id,
        provider.revision,
        cancel: _lifetime.future,
      );
      if (_closing) return;
      _deleted();
    } on EmailFailure catch (failure) {
      if (_closing) return;
      if (failure.uncertain) _deletePending = provider.id;
      _error = failure.message;
    } finally {
      if (!_closing) {
        _saving = false;
        _publish();
      }
    }
  }

  Future<void> reconcileDelete() async {
    final id = _deletePending;
    if (_closing || _saving || id == null) return;
    _cancelRead();
    _saving = true;
    _publish();
    try {
      final provider = await repository.getProvider(
        id,
        cancel: _lifetime.future,
      );
      if (_closing) return;
      _provider = provider;
      _deletePending = null;
      _error = null;
      _notice = 'The account still exists. Review it before deleting again.';
    } on EmailFailure catch (failure) {
      if (_closing) return;
      if (failure.kind == EmailFailureKind.notFound) {
        _deleted();
      } else {
        _error = failure.message;
      }
    } finally {
      if (!_closing) {
        _saving = false;
        _publish();
      }
    }
  }

  void _deleted() {
    _providers = _providers.where((p) => p.id != _selectedId).toList();
    _selectedId = null;
    _provider = null;
    _runs = [];
    _deletePending = null;
    _error = null;
    _notice =
        'Email account deleted. Accepted documents remain in this library.';
  }

  @override
  Future<void> close() async {
    _refresh.dispose();
    _closing = true;
    _readEpoch++;
    if (_readCancel case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
    if (!_lifetime.isCompleted) _lifetime.complete();
    await super.close();
  }
}
