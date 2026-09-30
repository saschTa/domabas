import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';

import '../../../domain/document/models/document_limits.dart';
import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/document/interfaces/document_repository.dart';
import '../../../domain/document/interfaces/document_file_saver.dart';
import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_capabilities.dart';
import '../../../domain/document/models/document_failure.dart';
import '../../../domain/document/models/document_processing.dart';

final class DocumentState {
  const DocumentState({
    this.document,
    this.ocr,
    this.bytes,
    this.loading = false,
    this.fileLoading = false,
    this.downloading = false,
    this.ocrLoading = false,
    this.saving = false,
    this.deleted = false,
    this.remotelyDeleted = false,
    this.editingMetadata = false,
    this.editingOcr = false,
    this.metadataDraft,
    this.ocrDraft,
    this.error,
    this.fileError,
    this.downloadError,
    this.ocrError,
    this.notice,
    this.conflict = false,
    this.reconcileRequired = false,
    this.pendingAIRetry,
  });
  final Document? document;
  final DocumentOcr? ocr;
  final Uint8List? bytes;
  final bool loading;
  final bool fileLoading;
  final bool downloading;
  final bool ocrLoading;
  final bool saving;
  final bool deleted;
  final bool remotelyDeleted;
  final bool editingMetadata;
  final bool editingOcr;
  final DocumentProperties? metadataDraft;
  final String? ocrDraft;
  final String? error;
  final String? fileError;
  final String? downloadError;
  final String? ocrError;
  final String? notice;
  final bool conflict;
  final bool reconcileRequired;
  final DocumentAIRetryRequest? pendingAIRetry;
  bool get metadataDirty =>
      editingMetadata &&
      metadataDraft != null &&
      document != null &&
      jsonEncode(metadataDraft!.values) !=
          jsonEncode(DocumentProperties.fromDocument(document!).values);
  bool get ocrDirty => editingOcr && ocrDraft != (ocr?.text ?? '');
  bool get dirty => metadataDirty || ocrDirty;
  DocumentState copyWith({
    Document? document,
    DocumentOcr? ocr,
    Uint8List? bytes,
    bool? loading,
    bool? fileLoading,
    bool? downloading,
    bool? ocrLoading,
    bool? saving,
    bool? deleted,
    bool? remotelyDeleted,
    bool? editingMetadata,
    bool? editingOcr,
    DocumentProperties? metadataDraft,
    String? ocrDraft,
    String? error,
    String? fileError,
    String? downloadError,
    String? ocrError,
    String? notice,
    bool? conflict,
    bool? reconcileRequired,
    bool clearError = false,
    bool clearFileError = false,
    bool clearDownloadError = false,
    bool clearOcrError = false,
    bool clearDrafts = false,
    bool clearBytes = false,
    bool clearOcr = false,
    DocumentAIRetryRequest? pendingAIRetry,
    bool clearAIRetry = false,
  }) => DocumentState(
    document: document ?? this.document,
    ocr: clearOcr ? null : ocr ?? this.ocr,
    bytes: clearBytes ? null : bytes ?? this.bytes,
    loading: loading ?? this.loading,
    fileLoading: fileLoading ?? this.fileLoading,
    downloading: downloading ?? this.downloading,
    ocrLoading: ocrLoading ?? this.ocrLoading,
    saving: saving ?? this.saving,
    deleted: deleted ?? this.deleted,
    remotelyDeleted: remotelyDeleted ?? this.remotelyDeleted,
    editingMetadata: editingMetadata ?? this.editingMetadata,
    editingOcr: editingOcr ?? this.editingOcr,
    metadataDraft: clearDrafts ? null : metadataDraft ?? this.metadataDraft,
    ocrDraft: clearDrafts ? null : ocrDraft ?? this.ocrDraft,
    error: clearError ? null : error ?? this.error,
    fileError: clearFileError ? null : fileError ?? this.fileError,
    downloadError: clearDownloadError
        ? null
        : downloadError ?? this.downloadError,
    ocrError: clearOcrError ? null : ocrError ?? this.ocrError,
    notice: notice,
    conflict: conflict ?? this.conflict,
    reconcileRequired: reconcileRequired ?? this.reconcileRequired,
    pendingAIRetry: clearAIRetry ? null : pendingAIRetry ?? this.pendingAIRetry,
  );
}

final class DocumentCubit extends Cubit<DocumentState> {
  DocumentCubit(
    this._repository, {
    required this.id,
    required this.capabilities,
    required this.onUpdated,
    required this.onDeleted,
    this.onMutation,
    this._fileSaver,
    String Function()? requestId,
  }) : _requestId = requestId ?? processingRequestId,
       super(const DocumentState());
  final String Function() _requestId;
  final DocumentRepository _repository;
  final DocumentFileSaver? _fileSaver;
  final String id;
  final DocumentCapabilities capabilities;
  final void Function(Document) onUpdated;
  final Future<void> Function(String) onDeleted;
  final Future<void> Function()? onMutation;
  final _lifetime = Completer<void>();
  Completer<void>? _fileRequest;
  bool _closing = false;
  int _generation = 0;
  int _ocrGeneration = 0;
  bool _metadataUncertain = false;
  bool _ocrUncertain = false;
  bool _deleteUncertain = false;
  bool _remoteLoading = false;
  int _remoteEpoch = 0;
  late final _refresh = AutomaticRefresh(
    read: refreshRemote,
    busy: () =>
        state.loading || state.ocrLoading || state.saving || _remoteLoading,
    interval: () => Duration(seconds: state.error == null ? 1 : 30),
  );

  void setActive(bool value) => _refresh.setActive(value);
  void invalidate() => _refresh.invalidate();

  Future<void> refreshRemote() async {
    if (_closing ||
        state.remotelyDeleted ||
        state.saving ||
        _remoteLoading ||
        !capabilities.read) {
      return;
    }
    final epoch = ++_remoteEpoch;
    _remoteLoading = true;
    try {
      final document = await _repository.getById(id, cancel: _lifetime.future);
      final ocr = capabilities.readOcr
          ? await _repository.getOcr(id, cancel: _lifetime.future)
          : null;
      if (_closing || epoch != _remoteEpoch || state.saving) return;
      final textChanged =
          state.editingOcr &&
          ocr != null &&
          ocr.revision != state.ocr?.revision;
      final propertiesChanged =
          state.editingMetadata &&
          state.document != null &&
          jsonEncode(DocumentProperties.fromDocument(document).values) !=
              jsonEncode(
                DocumentProperties.fromDocument(state.document!).values,
              );
      final originalChanged =
          state.document?.file?.sha256 != document.file?.sha256;
      if (originalChanged) _clearOriginal();
      onUpdated(document);
      emit(
        state.copyWith(
          document: document,
          clearBytes: originalChanged,
          ocr: state.editingOcr ? null : ocr,
          conflict: state.conflict || textChanged,
          notice: textChanged
              ? 'Extracted text changed elsewhere. Load latest and review before saving; your draft is preserved.'
              : propertiesChanged
              ? 'Properties changed elsewhere. Your draft is preserved.'
              : state.notice,
        ),
      );
      if (originalChanged && document.file != null && capabilities.download) {
        await loadOriginal();
      }
    } on DocumentFailure catch (failure) {
      if (_closing || epoch != _remoteEpoch) return;
      if (failure.kind == DocumentFailureKind.notFound) {
        _generation++;
        _ocrGeneration++;
        _remoteEpoch++;
        if (!_lifetime.isCompleted) _lifetime.complete();
        if (_fileRequest case final request? when !request.isCompleted) {
          request.complete();
        }
        _fileRequest = null;
        emit(
          state.copyWith(
            remotelyDeleted: true,
            loading: false,
            fileLoading: false,
            ocrLoading: false,
            clearBytes: true,
            clearOcr: true,
            notice: 'This document was deleted. Unsaved drafts remain available to copy.',
          ),
        );
        await onDeleted(id);
      } else {
        emit(state.copyWith(error: failure.message, notice: state.notice));
      }
    } finally {
      _remoteLoading = false;
    }
  }

  bool get _needsReconciliation =>
      _metadataUncertain || _ocrUncertain || _deleteUncertain;
  bool _uncertain(DocumentFailure failure) =>
      failure.kind == DocumentFailureKind.unavailable ||
      failure.kind == DocumentFailureKind.invalidResponse;

  Future<void> load() async {
    if (state.remotelyDeleted) return;
    if (_closing || !capabilities.read || state.saving) return;
    _remoteEpoch++;
    final generation = ++_generation;
    final reconcile = _metadataUncertain || _deleteUncertain;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final document = await _repository.getById(id, cancel: _lifetime.future);
      if (_closing || generation != _generation) return;
      onUpdated(document);
      _metadataUncertain = false;
      _deleteUncertain = false;
      emit(
        state.copyWith(
          document: document,
          loading: false,
          reconcileRequired: _needsReconciliation,
        ),
      );
      if (reconcile) _notifyMutation();
      await Future.wait([
        if (capabilities.readOcr) loadOcr(),
        if (document.file != null &&
            !document.file!.isEmail &&
            capabilities.download &&
            state.bytes == null)
          loadOriginal(),
      ]);
    } on DocumentFailure catch (failure) {
      if (!_closing &&
          generation == _generation &&
          _deleteUncertain &&
          failure.kind == DocumentFailureKind.notFound) {
        await _deleted();
        return;
      }
      if (!_closing && generation == _generation) {
        emit(state.copyWith(loading: false, error: failure.message));
      }
    }
  }

  Future<void> loadOcr() async {
    if (state.remotelyDeleted) return;
    if (_closing || !capabilities.readOcr || state.ocrLoading || state.saving) {
      return;
    }
    _remoteEpoch++;
    final generation = ++_ocrGeneration;
    final reconcile = _ocrUncertain || state.conflict;
    emit(state.copyWith(ocrLoading: true, clearOcrError: true));
    try {
      final ocr = await _repository.getOcr(id, cancel: _lifetime.future);
      if (!_closing && generation == _ocrGeneration) {
        _ocrUncertain = false;
        emit(
          state.copyWith(
            ocr: ocr,
            ocrLoading: false,
            conflict: false,
            reconcileRequired: _needsReconciliation,
            notice: state.editingOcr
                ? 'Latest version loaded. Your draft is preserved; review it before saving.'
                : null,
          ),
        );
        if (reconcile) _notifyMutation();
      }
    } on DocumentFailure catch (failure) {
      if (!_closing && generation == _ocrGeneration) {
        emit(state.copyWith(ocrLoading: false, ocrError: failure.message));
      }
    }
  }

  Future<void> loadOriginal() async {
    if (state.remotelyDeleted) return;
    if (_closing || !capabilities.download || state.document?.file == null) {
      return;
    }
    final previous = _fileRequest;
    if (previous != null && !previous.isCompleted) previous.complete();
    final request = _fileRequest = Completer<void>();
    emit(state.copyWith(fileLoading: true, clearFileError: true));
    try {
      final bytes = await _repository.download(
        state.document!.originalRef!,
        cancel: request.future,
      );
      if (!_closing &&
          !state.remotelyDeleted &&
          identical(request, _fileRequest)) {
        emit(
          state.copyWith(bytes: bytes.asUnmodifiableView(), fileLoading: false),
        );
      }
    } on DocumentFailure catch (failure) {
      if (!_closing &&
          !state.remotelyDeleted &&
          identical(request, _fileRequest)) {
        emit(
          state.copyWith(
            fileLoading: false,
            fileError: failure.kind == DocumentFailureKind.conflict
                ? 'The original is still processing. Refresh to try again.'
                : failure.message,
          ),
        );
      }
    }
  }

  bool get canDownloadOriginal =>
      !_closing &&
      capabilities.download &&
      _fileSaver != null &&
      state.document?.file != null &&
      !state.remotelyDeleted &&
      !state.deleted &&
      !state.fileLoading &&
      !state.downloading;

  Future<void> downloadOriginal() async {
    if (!canDownloadOriginal) return;
    final file = state.document!.file!;
    emit(state.copyWith(downloading: true, clearDownloadError: true));
    try {
      if (state.bytes == null) await loadOriginal();
      if (_closing || state.remotelyDeleted || state.deleted) return;
      final bytes = state.bytes;
      if (bytes == null) {
        emit(
          state.copyWith(
            downloadError:
                state.fileError ?? 'Could not download the original.',
          ),
        );
        return;
      }
      await _fileSaver!.save(file, bytes);
    } catch (_) {
      if (!_closing && !state.remotelyDeleted && !state.deleted) {
        emit(
          state.copyWith(
            downloadError: 'Could not save the original file. Try again.',
          ),
        );
      }
    } finally {
      if (!_closing) emit(state.copyWith(downloading: false));
    }
  }

  void editMetadata() {
    if (state.remotelyDeleted) return;
    if (!_closing &&
        capabilities.update &&
        state.document != null &&
        !state.saving) {
      emit(
        state.copyWith(
          editingMetadata: true,
          metadataDraft: DocumentProperties.fromDocument(state.document!),
          clearError: true,
        ),
      );
    }
  }

  void setMetadataDraft(DocumentProperties draft) {
    if (!_closing && state.editingMetadata) {
      emit(state.copyWith(metadataDraft: draft));
    }
  }

  void editOcr() {
    if (state.remotelyDeleted) return;
    if (!_closing &&
        capabilities.updateOcr &&
        state.document?.file != null &&
        state.ocr != null &&
        !state.saving) {
      emit(
        state.copyWith(
          editingOcr: true,
          ocrDraft: state.ocr!.text ?? '',
          clearError: true,
        ),
      );
    }
  }

  void setOcrDraft(String text) {
    if (!_closing && state.editingOcr) emit(state.copyWith(ocrDraft: text));
  }

  void discardDrafts() {
    if (!_closing && !state.saving) {
      emit(
        state.copyWith(
          editingMetadata: false,
          editingOcr: false,
          clearDrafts: true,
          conflict: false,
        ),
      );
    }
  }

  void cancelMetadata() {
    if (!_closing && !state.saving) {
      emit(state.copyWith(editingMetadata: false));
    }
  }

  void cancelOcr() {
    if (!_closing && !state.saving) {
      emit(state.copyWith(editingOcr: false, conflict: false));
    }
  }

  Future<bool> saveMetadata() async {
    if (state.remotelyDeleted) return false;
    if (_closing ||
        state.saving ||
        state.reconcileRequired ||
        !capabilities.update ||
        state.metadataDraft == null) {
      return false;
    }
    final draft = state.metadataDraft!;
    _remoteEpoch++;
    _generation++;
    emit(state.copyWith(saving: true, loading: false, clearError: true));
    try {
      final document = await _repository.update(
        state.document!,
        draft,
        cancel: _lifetime.future,
      );
      if (_closing) return false;
      onUpdated(document);
      _notifyMutation();
      emit(
        state.copyWith(
          document: document,
          saving: false,
          editingMetadata: false,
          notice: 'Properties saved.',
        ),
      );
      return true;
    } on DocumentFailure catch (failure) {
      if (_closing) return false;
      if (_uncertain(failure)) {
        try {
          final document = await _repository.getById(
            id,
            cancel: _lifetime.future,
          );
          if (_closing) return false;
          onUpdated(document);
          _notifyMutation();
          final saved =
              jsonEncode(DocumentProperties.fromDocument(document).values) ==
              jsonEncode(draft.values);
          emit(
            state.copyWith(
              document: document,
              saving: false,
              editingMetadata: !saved,
              error: saved ? null : 'The save was not confirmed. Latest properties loaded; review your draft before saving again.',
              clearError: saved,
              notice: saved ? 'Properties saved.' : null,
            ),
          );
          return saved;
        } on DocumentFailure {
          _metadataUncertain = true;
          if (!_closing) {
            emit(
              state.copyWith(
                saving: false,
                reconcileRequired: true,
                error: 'The save could not be confirmed. Reload before trying again; your draft is preserved.',
              ),
            );
          }
        }
      } else {
        emit(state.copyWith(saving: false, error: failure.message));
      }
      return false;
    }
  }

  Future<bool> saveOcr() async {
    if (state.remotelyDeleted) return false;
    if (_closing ||
        state.saving ||
        state.conflict ||
        state.reconcileRequired ||
        !capabilities.updateOcr ||
        state.ocrDraft == null ||
        state.ocr == null) {
      return false;
    }
    final text = state.ocrDraft!;
    _remoteEpoch++;
    if (utf8.encode(text).length > documentOCRByteLimit ||
        text.contains('\u0000')) {
      emit(
        state.copyWith(
          error: 'Extracted text must be at most 2 MiB and cannot contain NUL characters.',
        ),
      );
      return false;
    }
    _ocrGeneration++;
    emit(state.copyWith(saving: true, ocrLoading: false, clearError: true));
    try {
      final ocr = await _repository.updateOcr(
        id,
        state.ocr!.revision,
        text,
        cancel: _lifetime.future,
      );
      if (_closing) return false;
      _notifyMutation();
      emit(
        state.copyWith(
          ocr: ocr,
          saving: false,
          editingOcr: false,
          notice: 'Extracted text saved.',
        ),
      );
      return true;
    } on DocumentFailure catch (failure) {
      if (_closing) return false;
      if (_uncertain(failure)) {
        try {
          final latest = await _repository.getOcr(id, cancel: _lifetime.future);
          if (_closing) return false;
          _notifyMutation();
          final saved = latest.text == text;
          emit(
            state.copyWith(
              ocr: latest,
              saving: false,
              editingOcr: !saved,
              conflict: !saved,
              error: saved ? null : 'The save was not confirmed. Your draft is preserved; reload and review the latest text.',
              clearError: saved,
              notice: saved ? 'Extracted text saved.' : null,
            ),
          );
          return saved;
        } on DocumentFailure {
          _ocrUncertain = true;
          if (!_closing) {
            emit(
              state.copyWith(
                saving: false,
                reconcileRequired: true,
                error: 'The save could not be confirmed. Reload before trying again; your draft is preserved.',
              ),
            );
          }
        }
      } else {
        emit(
          state.copyWith(
            saving: false,
            error: failure.message,
            conflict: failure.kind == DocumentFailureKind.conflict,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> delete() async {
    if (state.remotelyDeleted) return false;
    if (_closing ||
        state.saving ||
        state.reconcileRequired ||
        !capabilities.delete) {
      return false;
    }
    _remoteEpoch++;
    emit(state.copyWith(saving: true, clearError: true));
    try {
      await _repository.delete(id, cancel: _lifetime.future);
      return await _deleted();
    } on DocumentFailure catch (failure) {
      if (_closing) return false;
      if (failure.kind == DocumentFailureKind.notFound) return _deleted();
      if (_uncertain(failure)) {
        try {
          await _repository.getById(id, cancel: _lifetime.future);
          if (!_closing) {
            _notifyMutation();
            emit(
              state.copyWith(
                saving: false,
                error: 'Deletion was not confirmed. The document still exists; you can try again.',
              ),
            );
          }
        } on DocumentFailure catch (readFailure) {
          if (readFailure.kind == DocumentFailureKind.notFound) {
            return _deleted();
          }
          _deleteUncertain = true;
          if (!_closing) {
            emit(
              state.copyWith(
                saving: false,
                reconcileRequired: true,
                error: 'Deletion could not be confirmed. Reload before trying again.',
              ),
            );
          }
        }
      } else {
        emit(state.copyWith(saving: false, error: failure.message));
      }
      return false;
    }
  }

  Future<bool> _deleted() async {
    if (_closing) return false;
    final deleted = onDeleted(id);
    final mutation = onMutation?.call();
    emit(
      state.copyWith(
        saving: false,
        deleted: true,
        clearDrafts: true,
        editingMetadata: false,
        editingOcr: false,
      ),
    );
    await deleted;
    await mutation;
    return true;
  }

  Future<bool> unlockPdf(String password) async {
    final processing = state.document?.processing;
    if (_closing ||
        state.remotelyDeleted ||
        state.saving ||
        !capabilities.unlock ||
        processing?.failureCode != 'encrypted_pdf') {
      return false;
    }
    _remoteEpoch++;
    emit(state.copyWith(saving: true, clearError: true));
    try {
      await _repository.unlock(
        id,
        processing!.generation,
        password,
        cancel: _lifetime.future,
      );
      if (_closing) return false;
      _clearOriginal();
      emit(
        state.copyWith(
          saving: false,
          clearBytes: true,
          clearFileError: true,
          notice: 'PDF unlocked. Processing queued.',
        ),
      );
      _notifyMutation();
      await load();
      return true;
    } on DocumentFailure catch (failure) {
      if (_closing) return false;
      emit(state.copyWith(saving: false, error: failure.message));
      if (_uncertain(failure) ||
          failure.kind == DocumentFailureKind.cancelled ||
          failure.kind == DocumentFailureKind.conflict) {
        _clearOriginal();
        emit(state.copyWith(clearBytes: true));
        await load();
        if (!_closing &&
            state.document?.processing?.failureCode == 'encrypted_pdf') {
          emit(state.copyWith(error: failure.message));
        }
      }
      return false;
    }
  }

  void _clearOriginal() {
    final request = _fileRequest;
    if (request != null && !request.isCompleted) request.complete();
    _fileRequest = null;
  }

  Future<void> retryProcessing() async {
    if (state.remotelyDeleted) return;
    if (_closing || state.saving || !capabilities.retry) return;
    _remoteEpoch++;
    emit(state.copyWith(saving: true, clearError: true));
    try {
      await _repository.retry(id, cancel: _lifetime.future);
      if (_closing) return;
      emit(state.copyWith(saving: false, notice: 'Processing queued.'));
      _notifyMutation();
      await load();
    } on DocumentFailure catch (failure) {
      if (!_closing) {
        emit(state.copyWith(saving: false, error: failure.message));
      }
    }
  }

  Future<void> retryAIProcessing() async {
    final processing = state.document?.processing;
    final ai = processing?.ai;
    if (_closing ||
        state.remotelyDeleted ||
        state.saving ||
        !capabilities.retry ||
        processing?.state != 'ready' ||
        (state.pendingAIRetry == null && ai?.canRetry != true)) {
      return;
    }
    final request =
        state.pendingAIRetry ??
        DocumentAIRetryRequest(_requestId(), ai!.configurationRevision);
    _remoteEpoch++;
    emit(
      state.copyWith(saving: true, clearError: true, pendingAIRetry: request),
    );
    try {
      await _repository.retryAI(id, request, cancel: _lifetime.future);
      if (_closing) return;
      emit(
        state.copyWith(
          saving: false,
          clearAIRetry: true,
          notice: 'AI processing queued. This document stays searchable.',
        ),
      );
      _notifyMutation();
      await load();
    } on DocumentFailure catch (failure) {
      if (_closing) return;
      final uncertain = {
        DocumentFailureKind.unavailable,
        DocumentFailureKind.invalidResponse,
        DocumentFailureKind.cancelled,
      }.contains(failure.kind);
      emit(
        state.copyWith(
          saving: false,
          clearAIRetry: !uncertain,
          error: uncertain
              ? 'AI retry acceptance could not be confirmed. Retry the same request safely.'
              : failure.message,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    _refresh.dispose();
    _remoteEpoch++;
    if (_closing) return;
    _closing = true;
    _generation++;
    if (!_lifetime.isCompleted) _lifetime.complete();
    if (_fileRequest case final request? when !request.isCompleted) {
      request.complete();
    }
    await super.close();
  }

  void _notifyMutation() {
    if (!_closing && onMutation != null) unawaited(onMutation!());
  }
}
