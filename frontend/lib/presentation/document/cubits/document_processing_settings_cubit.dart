import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/document/interfaces/document_processing_repository.dart';
import '../../../domain/document/models/document_processing.dart';

final class DocumentProcessingSettingsState {
  DocumentProcessingSettingsState({
    this.configuration,
    Iterable<DocumentReindexBatch> batches = const [],
    this.nextCursor,
    this.language,
    this.segmentation,
    this.draftRevision,
    this.loading = false,
    this.saving = false,
    this.error,
    this.notice,
    this.pendingRequest,
    this.reconcileRequired = false,
    this.browsingHistory = false,
    this.llm = const DocumentLLMSettingsDraft(),
    this.modelContext,
    this.loadingModelContext = false,
    this.modelContextError,
  }) : batches = List.unmodifiable(batches);
  final DocumentProcessingConfiguration? configuration;
  final List<DocumentReindexBatch> batches;
  final String? nextCursor, language, segmentation, error, notice;
  final int? draftRevision;
  final bool loading, saving, reconcileRequired, browsingHistory;
  final DocumentReindexRequest? pendingRequest;
  final DocumentLLMSettingsDraft llm;
  final DocumentModelContext? modelContext;
  final bool loadingModelContext;
  final String? modelContextError;
  bool get dirty =>
      configuration != null &&
      (language != configuration!.pipeline.configuration.language ||
          segmentation != configuration!.pipeline.configuration.segmentation ||
          llm.changed(configuration!.llm));
}

final class DocumentProcessingSettingsCubit
    extends Cubit<DocumentProcessingSettingsState> {
  DocumentProcessingSettingsCubit(
    this._repository,
    this._launcher, {
    required this.allowed,
    String Function()? requestId,
  }) : _requestId = requestId ?? processingRequestId,
       super(DocumentProcessingSettingsState());
  final DocumentProcessingRepository _repository;
  final ExternalLinkLauncher _launcher;
  final bool allowed;
  final String Function() _requestId;
  bool _active = false, _loading = false, _saving = false;
  bool _olderBatches = false;
  bool _polling = false;
  int _epoch = 0, _reads = 0;
  late final _refresh = AutomaticRefresh(
    read: () => load(poll: true),
    busy: () => _loading || _saving,
    interval: () => Duration(seconds: _error == null ? 1 : 30),
  );
  void invalidate() => _refresh.invalidate();

  Completer<void>? _readCancel, _writeCancel;
  DocumentProcessingConfiguration? _configuration;
  List<DocumentReindexBatch> _batches = const [];
  String? _cursor, _language, _segmentation, _error, _notice;
  int? _draftRevision;
  DocumentReindexRequest? _pending;
  DocumentLLMSettingsDraft _llm = const DocumentLLMSettingsDraft();
  int _contextEpoch = 0;
  Completer<void>? _contextCancel;
  DocumentModelContext? _modelContext;
  bool _loadingModelContext = false;
  String? _modelContextError;
  ({String language, String segmentation, DocumentLLMSettingsDraft? llm})?
  _uncertainSettings;
  bool get active => _active && !isClosed && allowed;
  bool get _blockingRead => _loading && (!_polling || _configuration == null);
  bool get canSave =>
      active &&
      !_blockingRead &&
      !_saving &&
      _configuration != null &&
      _uncertainSettings == null &&
      (!_llm.changed(_configuration!.llm) || _llm.valid) &&
      state.dirty;
  bool get canRequest =>
      active &&
      !_blockingRead &&
      !_saving &&
      _configuration != null &&
      _pending == null &&
      _uncertainSettings == null;

  void setActive(bool value) {
    if (isClosed || value == _active) return;
    _active = value;
    if (!value) _clearModelContext();
    _refresh.setActive(value);
    _epoch++;
    _cancel(_readCancel);
    _cancel(_writeCancel);
    _loading = _saving = false;
    _publish();
    if (active) unawaited(load(poll: true));
  }

  void edit({String? language, String? segmentation}) {
    if (!active ||
        _saving ||
        _uncertainSettings != null ||
        _configuration == null) {
      return;
    }
    _draftRevision ??= _configuration!.pipeline.configuration.revision;
    if (language != null) _language = language;
    if (segmentation != null) _segmentation = segmentation;
    _error = null;
    _notice = null;
    _publish();
  }

  void resetDraft() {
    if (_saving || _configuration == null || _uncertainSettings != null) return;
    _language = _configuration!.pipeline.configuration.language;
    _segmentation = _configuration!.pipeline.configuration.segmentation;
    _llm = DocumentLLMSettingsDraft.fromConfiguration(_configuration!.llm);
    _draftRevision = null;
    _error = null;
    _publish();
  }

  void editLLM({
    bool? enabled,
    bool? invoiceEnabled,
    bool? propertyThinkingEnabled,
    bool? invoiceThinkingEnabled,
    bool? lmStudioCompatibility,
    String? provider,
    String? model,
    String? baseUrl,
    String? apiKey,
    bool? clearApiKey,
    String? contextLength,
  }) {
    if (!active ||
        _saving ||
        _uncertainSettings != null ||
        _configuration == null) {
      return;
    }
    _draftRevision ??= _configuration!.pipeline.configuration.revision;
    _llm = _llm.copyWith(
      enabled: enabled,
      invoiceEnabled: invoiceEnabled,
      propertyThinkingEnabled: propertyThinkingEnabled,
      invoiceThinkingEnabled: invoiceThinkingEnabled,
      lmStudioCompatibility: lmStudioCompatibility,
      provider: provider,
      model: model,
      baseUrl: baseUrl,
      apiKey: clearApiKey == true || provider == 'ollama' ? '' : apiKey,
      clearApiKey: apiKey != null && apiKey.isNotEmpty ? false : clearApiKey,
      contextLength: contextLength,
    );
    _error = null;
    _notice = null;
    _publish();
  }

  Future<void> load({bool more = false, bool poll = false}) async {
    if (!poll) _cancelBackgroundRead();
    if (!active || _loading || _saving) return;
    if (more && _cursor == null) return;
    _loading = true;
    _polling = poll;
    if (!poll) _error = null;
    final epoch = _epoch, read = ++_reads;
    final cancel = _readCancel = Completer<void>();
    _publish();
    try {
      final config = await _repository.getSystemConfiguration(
        cancel: cancel.future,
      );
      final batches = await _repository.listSystemBatches(
        cursor: more ? _cursor : null,
        cancel: cancel.future,
      );
      final updates = <DocumentReindexBatch>[];
      if (poll && _olderBatches) {
        final candidates = _batches.where((batch) => batch.active).toList();
        for (final batch in candidates) {
          updates.add(
            await _repository.getSystemBatch(batch.id, cancel: cancel.future),
          );
        }
      }
      if (!_current(epoch) || read != _reads) return;
      _error = null;
      _acceptConfiguration(config);
      if (poll && _olderBatches) {
        final byId = {
          for (final batch in [...batches.items, ...updates]) batch.id: batch,
        };
        _batches = List.unmodifiable(
          _batches.map((batch) => byId[batch.id] ?? batch),
        );
      } else {
        final seen = <String>{};
        _batches = List.unmodifiable(
          [
            if (more) ..._batches,
            ...batches.items,
          ].where((b) => seen.add(b.id)),
        );
        _cursor = batches.nextCursor;
        _olderBatches = more;
      }
      if (_pending != null && _batches.any((b) => b.id == _pending!.id)) {
        _pending = null;
        _notice = 'Reindex request accepted.';
      }
    } on DocumentProcessingFailure catch (failure) {
      if (_current(epoch) &&
          read == _reads &&
          failure.kind != DocumentProcessingFailureKind.cancelled) {
        _error = failure.message;
      }
    } finally {
      if (_current(epoch) && read == _reads) {
        _loading = false;
        _publish();
      }
    }
  }

  Future<void> checkModelContext() async {
    final model = _llm.model.trim();
    if (!active ||
        _saving ||
        _loadingModelContext ||
        _llm.provider != 'ollama' ||
        model.isEmpty) {
      return;
    }
    _clearModelContext();
    final epoch = _contextEpoch;
    final cancel = _contextCancel = Completer<void>();
    _loadingModelContext = true;
    _publish();
    try {
      final result = await _repository.modelContext(
        model,
        cancel: cancel.future,
      );
      if (!active || epoch != _contextEpoch) return;
      _modelContext = result;
    } on DocumentProcessingFailure catch (_) {
      if (!active || epoch != _contextEpoch) return;
      _modelContextError = 'Could not check this model’s context limit. Check that the model is installed, then retry.';
    } finally {
      if (active && epoch == _contextEpoch) {
        _loadingModelContext = false;
        _publish();
      }
    }
  }

  void _clearModelContext() {
    _contextEpoch++;
    _cancel(_contextCancel);
    _modelContext = null;
    _loadingModelContext = false;
    _modelContextError = null;
  }

  void _acceptConfiguration(DocumentProcessingConfiguration config) {
    _configuration = config;
    final pending = _uncertainSettings;
    if (pending != null) {
      _uncertainSettings = null;
      if (config.pipeline.configuration.language == pending.language &&
          config.pipeline.configuration.segmentation == pending.segmentation &&
          (pending.llm == null ||
              (pending.llm!.matches(config.llm) &&
                  (!pending.llm!.clearApiKey ||
                      !config.llm.credentialConfigured)))) {
        _draftRevision = null;
        if (pending.llm?.apiKey.isNotEmpty ?? false) {
          _error = 'Settings reloaded. A stored API key cannot be checked here. Enter it again if you need to replace it.';
        } else {
          _notice = 'Settings confirmed. Changed settings schedule the affected pipeline automatically.';
        }
      } else {
        _error = 'The saved settings differ from your draft. Review the latest values before saving.';
      }
    }
    if (_language == config.pipeline.configuration.language &&
        _segmentation == config.pipeline.configuration.segmentation &&
        !_llm.changed(config.llm)) {
      _draftRevision = null;
    }
    if (_draftRevision == null) {
      _language = config.pipeline.configuration.language;
      _segmentation = config.pipeline.configuration.segmentation;
      _llm = DocumentLLMSettingsDraft.fromConfiguration(config.llm);
    }
  }

  Future<void> save() async {
    if (!canSave) return;
    _cancelBackgroundRead();
    final language = _language!, segmentation = _segmentation!;
    final revision =
        _draftRevision ?? _configuration!.pipeline.configuration.revision;
    final llm = _llm.changed(_configuration!.llm) ? _llm : null;
    _uncertainSettings = (
      language: language,
      segmentation: segmentation,
      llm: llm,
    );
    _saving = true;
    _error = null;
    _notice = null;
    final epoch = _epoch, cancel = _writeCancel = Completer<void>();
    _publish();
    try {
      final config = await _repository.updateSystemConfiguration(
        language: language,
        segmentation: segmentation,
        expectedRevision: revision,
        llm: llm,
        cancel: cancel.future,
      );
      if (!_current(epoch)) return;
      _draftRevision = null;
      _uncertainSettings = null;
      _acceptConfiguration(config);
      _notice = 'Settings saved.';
    } on DocumentProcessingFailure catch (failure) {
      if (!_current(epoch)) return;
      if ({
        DocumentProcessingFailureKind.conflict,
        DocumentProcessingFailureKind.rejected,
        DocumentProcessingFailureKind.forbidden,
      }.contains(failure.kind)) {
        _uncertainSettings = null;
        _error = failure.message;
      } else {
        _error = 'The save could not be confirmed. Refresh to check the saved settings before trying again.';
      }
    } finally {
      if (_current(epoch)) {
        _saving = false;
        _publish();
      }
    }
  }

  Future<void> requestReindex({bool retry = false}) async {
    if (!active ||
        _saving ||
        _blockingRead ||
        _configuration == null ||
        _uncertainSettings != null ||
        (retry ? _pending == null : !canRequest)) {
      return;
    }
    _cancelBackgroundRead();
    final request =
        _pending ??
        DocumentReindexRequest(
          _requestId(),
          _configuration!.pipeline.configuration.revision,
        );
    _pending = request;
    _saving = true;
    _error = null;
    _notice = null;
    final epoch = _epoch, cancel = _writeCancel = Completer<void>();
    _publish();
    try {
      final batch = await _repository.createSystemBatch(
        request,
        cancel: cancel.future,
      );
      if (!_current(epoch)) return;
      _pending = null;
      _batches = List.unmodifiable([
        batch,
        ..._batches.where((b) => b.id != batch.id),
      ]);
      _notice = 'Reindex request accepted for all library originals.';
    } on DocumentProcessingFailure catch (failure) {
      if (!_current(epoch)) return;
      if ({
        DocumentProcessingFailureKind.conflict,
        DocumentProcessingFailureKind.forbidden,
        DocumentProcessingFailureKind.rejected,
        DocumentProcessingFailureKind.notFound,
      }.contains(failure.kind)) {
        _pending = null;
      }
      _error = _pending != null
          ? 'Acceptance could not be confirmed. Retry safely to check the same request.'
          : failure.message;
    } finally {
      if (_current(epoch)) {
        _saving = false;
        _publish();
      }
    }
  }

  Future<void> openDashboard() async {
    final uri = _configuration?.dashboardUrl;
    if (!active || uri == null) return;
    final epoch = _epoch;
    try {
      final opened = await _launcher.open(uri);
      if (_current(epoch) && !opened) {
        _error = 'The dashboard link could not be opened on this device.';
        _publish();
      }
    } catch (_) {
      if (_current(epoch)) {
        _error = 'The dashboard link could not be opened on this device.';
        _publish();
      }
    }
  }

  bool _current(int epoch) => active && epoch == _epoch;
  void _cancelBackgroundRead() {
    if (!_loading || _blockingRead) return;
    _reads++;
    _cancel(_readCancel);
    _loading = false;
    _refresh.invalidate();
  }

  void _publish() {
    if (!isClosed) {
      if (_llm.model.trim() != state.llm.model.trim() ||
          _llm.provider != state.llm.provider) {
        _clearModelContext();
      }
      emit(
        DocumentProcessingSettingsState(
          configuration: _configuration,
          batches: _batches,
          nextCursor: _cursor,
          language: _language,
          segmentation: _segmentation,
          draftRevision: _draftRevision,
          loading: _blockingRead,
          saving: _saving,
          error: _error,
          notice: _notice,
          pendingRequest: _pending,
          reconcileRequired: _uncertainSettings != null,
          browsingHistory: _olderBatches,
          llm: _llm,
          modelContext: _modelContext,
          loadingModelContext: _loadingModelContext,
          modelContextError: _modelContextError,
        ),
      );
    }
  }

  static void _cancel(Completer<void>? value) {
    if (value != null && !value.isCompleted) value.complete();
  }

  @override
  Future<void> close() {
    _refresh.dispose();
    setActive(false);
    return super.close();
  }
}
