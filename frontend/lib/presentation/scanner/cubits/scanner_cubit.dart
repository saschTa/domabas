import 'dart:async';
import 'dart:math' as math;

import 'package:bloc/bloc.dart';

import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_upload_validation.dart';
import '../../../domain/scanner/interfaces/scan_draft_repository.dart';
import '../../../domain/scanner/interfaces/scanner_camera.dart';
import '../../../domain/scanner/models/scan.dart';

enum ScannerStage { review, camera, correction }

final class ScannerState {
  ScannerState({
    this.draft,
    this.properties,
    this.camera = const ScanCameraState(),
    this.stage = ScannerStage.review,
    this.capture,
    this.corners,
    this.loading = true,
    this.busy = false,
    this.submitting = false,
    this.saving = false,
    this.dirty = false,
    this.error,
    Map<String, String> validation = const {},
    this.validationAttempt = 0,
    this.discarded = false,
    this.pendingPages = 0,
    this.batchTotalPages = 0,
  }) : validation = Map.unmodifiable(validation);

  final ScanDraft? draft;
  final DocumentProperties? properties;
  final ScanCameraState camera;
  final ScannerStage stage;
  final ScanCapture? capture;
  final ScanCorners? corners;
  final bool loading;
  final bool busy;
  final bool submitting;
  final bool saving;
  final bool dirty;
  final String? error;
  final Map<String, String> validation;
  final int validationAttempt;
  final bool discarded;
  final int pendingPages;
  final int batchTotalPages;
  bool get editable => draft?.editable == true && !busy && !loading;
  bool get validCorners =>
      capture != null &&
      corners?.validFor(capture!.width, capture!.height) == true;

  ScannerState copyWith({
    ScanDraft? draft,
    DocumentProperties? properties,
    ScanCameraState? camera,
    ScannerStage? stage,
    ScanCapture? capture,
    ScanCorners? corners,
    bool clearCapture = false,
    bool? loading,
    bool? busy,
    bool? submitting,
    bool? saving,
    bool? dirty,
    String? error,
    bool clearError = false,
    Map<String, String>? validation,
    int? validationAttempt,
    bool? discarded,
    int? pendingPages,
    int? batchTotalPages,
  }) => ScannerState(
    draft: draft ?? this.draft,
    properties: properties ?? this.properties,
    camera: camera ?? this.camera,
    stage: stage ?? this.stage,
    capture: clearCapture ? null : capture ?? this.capture,
    corners: clearCapture ? null : corners ?? this.corners,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    submitting: submitting ?? this.submitting,
    saving: saving ?? this.saving,
    dirty: dirty ?? this.dirty,
    error: clearError ? null : error ?? this.error,
    validation: validation ?? this.validation,
    validationAttempt: validationAttempt ?? this.validationAttempt,
    discarded: discarded ?? this.discarded,
    pendingPages: pendingPages ?? this.pendingPages,
    batchTotalPages: batchTotalPages ?? this.batchTotalPages,
  );
}

final class ScannerCubit extends Cubit<ScannerState> {
  ScannerCubit({
    required ScannerCamera camera,
    required this._repository,
    required this.allowed,
    this.onAccepted,
  }) : _camera = camera,
       super(ScannerState(camera: camera.state)) {
    _cameraSubscription = _camera.states.listen((value) {
      if (!_closing) emit(state.copyWith(camera: value));
    });
  }

  final ScannerCamera _camera;
  bool get usesSystemCapture => _camera.usesSystemCapture;
  bool get supportsBatchCapture => _camera is ScannerBatchCamera;
  String? get systemCaptureNotice => switch (_camera) {
    final ScannerSystemCapture source => source.systemCaptureNotice,
    _ => null,
  };
  final ScanDraftRepository _repository;
  final bool allowed;
  final void Function()? onAccepted;
  late final StreamSubscription<ScanCameraState> _cameraSubscription;
  Timer? _saveTimer;
  DocumentProperties? _pendingProperties;
  Future<bool>? _saving;
  bool _closing = false;
  bool _foreground = true;
  bool _acceptedNotified = false;
  int _cameraRevision = 0;
  int _cameraAppliedRevision = 0;
  Future<void>? _cameraTransition;
  bool _takingCapture = false;
  bool _submissionCancelled = false;
  bool get _canEdit => allowed && !_closing && state.editable;

  Future<void> restore() async {
    if (_closing || state.busy || state.draft != null) return;
    if (!allowed) {
      emit(
        state.copyWith(
          loading: false,
          error: 'You do not have permission to upload documents.',
        ),
      );
      return;
    }
    emit(state.copyWith(loading: true, busy: true, clearError: true));
    try {
      final draft = await _repository.restore();
      if (_closing) return;
      emit(
        state.copyWith(
          draft: draft,
          properties: draft.properties,
          loading: false,
          busy: false,
        ),
      );
      _notifyAccepted(draft);
    } catch (error) {
      if (!_closing) {
        emit(
          state.copyWith(loading: false, busy: false, error: _message(error)),
        );
      }
    }
  }

  void setProperties(DocumentProperties properties) {
    if (!_canEdit) return;
    _pendingProperties = properties;
    emit(
      state.copyWith(
        properties: properties,
        dirty: true,
        clearError: true,
        validation: state.validation.isEmpty
            ? const {}
            : DocumentUploadValidation.validate(properties),
      ),
    );
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(flushProperties());
    });
  }

  Future<bool> flushProperties() {
    _saveTimer?.cancel();
    if (_closing || !allowed) return Future.value(false);
    if (_saving case final saving?) return saving;
    final completion = Completer<bool>();
    _saving = completion.future;
    unawaited(() async {
      var saved = true;
      while (!_closing && _pendingProperties != null) {
        final properties = _pendingProperties!;
        _pendingProperties = null;
        emit(state.copyWith(saving: true));
        try {
          final draft = await _repository.saveProperties(properties);
          if (_closing) break;
          emit(state.copyWith(draft: draft, dirty: _pendingProperties != null));
        } catch (error) {
          if (!_closing) {
            _pendingProperties ??= properties;
            emit(state.copyWith(dirty: true, error: _message(error)));
          }
          saved = false;
          break;
        }
      }
      if (!_closing) emit(state.copyWith(saving: false));
      _saving = null;
      completion.complete(saved && !_closing);
    }());
    return completion.future;
  }

  Future<void> addPage() async {
    if (!_canEdit ||
        state.capture != null ||
        state.pendingPages > 0 ||
        state.draft!.pages.length >= 20) {
      return;
    }
    emit(
      state.copyWith(stage: ScannerStage.camera, busy: true, clearError: true),
    );
    try {
      await _reconcileCamera();
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    } finally {
      if (!_closing) emit(state.copyWith(busy: false));
    }
    if (_camera.usesSystemCapture && !_closing) await capture();
  }

  Future<void> setForeground(bool foreground) async {
    _foreground = foreground;
    if (_closing || !allowed) return;
    try {
      await _reconcileCamera();
      if (!foreground) await flushProperties();
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    }
  }

  Future<void> _reconcileCamera() {
    _cameraRevision++;
    if (_cameraTransition case final transition?) return transition;
    final completion = Completer<void>();
    _cameraTransition = completion.future;
    unawaited(() async {
      try {
        while (!_closing && _cameraAppliedRevision != _cameraRevision) {
          final revision = _cameraRevision;
          if (_foreground &&
              state.stage == ScannerStage.camera &&
              !_takingCapture) {
            await _camera.start();
          } else {
            await _camera.suspend();
          }
          _cameraAppliedRevision = revision;
        }
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _cameraTransition = null;
      }
    }());
    return completion.future;
  }

  Future<void> capture() async {
    if (!_canEdit ||
        !_foreground ||
        state.stage != ScannerStage.camera ||
        state.camera.status != ScanCameraStatus.ready) {
      return;
    }
    emit(state.copyWith(busy: true, clearError: true));
    _takingCapture = true;
    try {
      if (_camera.usesSystemCapture) {
        final saved = await flushProperties();
        if (_closing) return;
        if (!saved || !_foreground) {
          emit(state.copyWith(stage: ScannerStage.review));
          await _reconcileCamera();
          return;
        }
      }
      if (_camera case final ScannerBatchCamera batch) {
        await batch.beginBatch(maxPages: 20 - state.draft!.pages.length);
        if (_closing) return;
        emit(
          state.copyWith(
            pendingPages: batch.pendingPageCount,
            batchTotalPages: batch.pendingPageCount,
            stage: ScannerStage.review,
          ),
        );
        await _importPendingPages(batch);
        return;
      }
      final capture = await _camera.capture();
      if (_closing) return;
      final corners = capture.corners.validFor(capture.width, capture.height)
          ? capture.corners
          : ScanCorners.fullImage();
      emit(
        state.copyWith(
          capture: capture,
          corners: corners,
          stage: ScannerStage.correction,
        ),
      );
      await _reconcileCamera();
      if (capture.processed && !_closing) {
        await _keepPage(capture, corners);
      }
    } on ScanCancelled {
      if (!_closing) {
        emit(
          state.copyWith(
            stage: ScannerStage.review,
            clearCapture: true,
            clearError: true,
            pendingPages: _pendingPageCount,
          ),
        );
      }
    } catch (error) {
      if (!_closing) {
        emit(
          state.copyWith(
            stage: _camera.usesSystemCapture && state.capture == null
                ? ScannerStage.review
                : state.stage,
            error: _message(error),
            pendingPages: _pendingPageCount,
          ),
        );
      }
    } finally {
      _takingCapture = false;
      if (!_closing && state.stage == ScannerStage.camera) {
        try {
          await _reconcileCamera();
        } catch (error) {
          if (!_closing) emit(state.copyWith(error: _message(error)));
        }
      }
      if (!_closing) emit(state.copyWith(busy: false));
    }
  }

  void moveCorner(int index, ScanPoint point) {
    if (!_canEdit ||
        state.capture?.processed == true ||
        state.stage != ScannerStage.correction ||
        index < 0 ||
        index > 3 ||
        !point.x.isFinite ||
        !point.y.isFinite) {
      return;
    }
    final points = [...state.corners!.points];
    points[index] = ScanPoint(point.x.clamp(0, 1), point.y.clamp(0, 1));
    emit(state.copyWith(corners: ScanCorners(points), clearError: true));
  }

  void resetCorners() {
    if (_canEdit && state.capture != null && !state.capture!.processed) {
      emit(state.copyWith(corners: ScanCorners.fullImage()));
    }
  }

  void moveEdge(int index, ScanPoint midpoint) {
    if (!_canEdit ||
        state.capture?.processed == true ||
        state.stage != ScannerStage.correction ||
        index < 0 ||
        index > 3 ||
        !midpoint.x.isFinite ||
        !midpoint.y.isFinite) {
      return;
    }
    final points = [...state.corners!.points];
    final next = (index + 1) % 4;
    final first = points[index];
    final second = points[next];
    final dx = (midpoint.x - (first.x + second.x) / 2).clamp(
      -math.min(first.x, second.x),
      1 - math.max(first.x, second.x),
    );
    final dy = (midpoint.y - (first.y + second.y) / 2).clamp(
      -math.min(first.y, second.y),
      1 - math.max(first.y, second.y),
    );
    points[index] = ScanPoint(first.x + dx, first.y + dy);
    points[next] = ScanPoint(second.x + dx, second.y + dy);
    emit(state.copyWith(corners: ScanCorners(points), clearError: true));
  }

  Future<void> keepPage() async {
    if (state.pendingPages > 0) {
      await retryPendingPages();
      return;
    }
    if (!_canEdit || !state.validCorners) return;
    final capture = state.capture!;
    final corners = state.corners!;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _keepPage(capture, corners);
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    } finally {
      if (!_closing) emit(state.copyWith(busy: false));
    }
  }

  Future<void> _keepPage(ScanCapture capture, ScanCorners corners) async {
    if (!await flushProperties() || _closing) return;
    final draft = await _repository.keepPage(capture, corners);
    if (_closing) return;
    emit(
      state.copyWith(
        draft: draft,
        clearCapture: true,
        stage: ScannerStage.review,
      ),
    );
    await _camera.releaseCapture(capture.id);
  }

  int get _pendingPageCount => switch (_camera) {
    final ScannerBatchCamera batch => batch.pendingPageCount,
    _ => 0,
  };

  Future<void> _importPendingPages(ScannerBatchCamera batch) async {
    while (!_closing && batch.pendingPageCount > 0) {
      final capture = await batch.captureNextPage();
      if (_closing) return;
      emit(
        state.copyWith(
          capture: capture,
          corners: capture.corners,
          stage: ScannerStage.correction,
          pendingPages: batch.pendingPageCount,
        ),
      );
      if (!await flushProperties() || _closing) return;
      final draft = await _repository.keepPage(capture, capture.corners);
      if (_closing) return;
      emit(state.copyWith(draft: draft));
      await batch.acknowledgePage(capture.id);
      if (_closing) return;
      emit(
        state.copyWith(
          clearCapture: true,
          stage: ScannerStage.review,
          pendingPages: batch.pendingPageCount,
        ),
      );
    }
  }

  Future<void> retryPendingPages() async {
    if (!_canEdit || !_foreground || state.pendingPages == 0) return;
    final camera = switch (_camera) {
      final ScannerBatchCamera batch => batch,
      _ => null,
    };
    if (camera == null) return;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _importPendingPages(camera);
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    } finally {
      if (!_closing) {
        emit(
          state.copyWith(busy: false, pendingPages: camera.pendingPageCount),
        );
      }
    }
  }

  Future<void> discardPendingPages() async {
    if (!_canEdit || state.pendingPages == 0) return;
    final camera = switch (_camera) {
      final ScannerBatchCamera batch => batch,
      _ => null,
    };
    if (camera == null) return;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await camera.discardPendingPages();
      if (_closing) return;
      emit(
        state.copyWith(
          clearCapture: true,
          stage: ScannerStage.review,
          pendingPages: 0,
          batchTotalPages: 0,
        ),
      );
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    } finally {
      if (!_closing) {
        emit(
          state.copyWith(busy: false, pendingPages: camera.pendingPageCount),
        );
      }
    }
  }

  Future<void> retake() async {
    if (!_canEdit || state.capture == null || state.pendingPages > 0) return;
    final capture = state.capture!;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _camera.releaseCapture(capture.id);
      if (_closing) return;
      emit(state.copyWith(clearCapture: true, stage: ScannerStage.camera));
      await _reconcileCamera();
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    } finally {
      if (!_closing) emit(state.copyWith(busy: false));
    }
    if (_camera.usesSystemCapture && !_closing) await this.capture();
  }

  Future<void> showReview() async {
    if (_closing || !allowed || state.busy || state.capture != null) return;
    emit(state.copyWith(stage: ScannerStage.review));
    try {
      await _reconcileCamera();
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    }
  }

  Future<void> removePage(String id) async {
    if (!_canEdit || !state.draft!.pages.any((page) => page.id == id)) return;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      if (!await flushProperties() || _closing) return;
      final draft = await _repository.removePage(id);
      if (!_closing) emit(state.copyWith(draft: draft));
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    } finally {
      if (!_closing) emit(state.copyWith(busy: false));
    }
  }

  Future<void> movePage(String id, int finalIndex) async {
    if (!_canEdit || state.stage != ScannerStage.review) return;
    final pages = state.draft!.pages;
    final originalIndex = pages.indexWhere((page) => page.id == id);
    if (originalIndex < 0 ||
        finalIndex < 0 ||
        finalIndex >= pages.length ||
        originalIndex == finalIndex) {
      return;
    }
    emit(state.copyWith(busy: true, clearError: true));
    try {
      if (!await flushProperties() || _closing) return;
      final draft = await _repository.movePage(id, finalIndex);
      if (!_closing) emit(state.copyWith(draft: draft));
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    } finally {
      if (!_closing) emit(state.copyWith(busy: false));
    }
  }

  Future<void> submit() async {
    if (!_canEdit ||
        state.stage != ScannerStage.review ||
        state.pendingPages > 0 ||
        state.draft!.pages.isEmpty) {
      return;
    }
    final validation = DocumentUploadValidation.validate(state.properties!);
    emit(
      state.copyWith(
        validation: validation,
        validationAttempt: state.validationAttempt + 1,
        clearError: true,
      ),
    );
    if (validation.isNotEmpty) return;
    await _submit(retry: false);
  }

  Future<void> retryUpload() async {
    if (_closing ||
        !allowed ||
        state.busy ||
        state.draft?.status != ScanDraftStatus.uncertain) {
      return;
    }
    await _submit(retry: true);
  }

  Future<void> _submit({required bool retry}) async {
    _submissionCancelled = false;
    emit(state.copyWith(busy: true, submitting: true, clearError: true));
    try {
      if (!retry && !await flushProperties()) return;
      if (_closing) return;
      if (_submissionCancelled) {
        emit(
          state.copyWith(
            error:
                'Upload cancelled before sending. Your saved scan is retained.',
          ),
        );
        return;
      }
      final result = await (retry
          ? _repository.retryUpload()
          : _repository.submit());
      if (_closing) return;
      emit(
        state.copyWith(
          draft: result.draft,
          properties: result.draft.properties,
        ),
      );
      _notifyAccepted(result.draft);
    } catch (error) {
      if (!_closing) {
        try {
          final draft = await _repository.restore();
          if (!_closing) {
            emit(
              state.copyWith(
                draft: draft,
                properties: draft.properties,
                error: _message(error),
              ),
            );
            _notifyAccepted(draft);
          }
        } catch (_) {
          if (!_closing) {
            final previous = state.draft!;
            emit(
              state.copyWith(
                draft: ScanDraft(
                  id: previous.id,
                  revision: previous.revision,
                  properties: previous.properties,
                  pages: previous.pages,
                  status: ScanDraftStatus.blocked,
                  message: 'The upload state could not be restored. Close and reopen this scan before taking further action.',
                ),
                error: _message(error),
              ),
            );
          }
        }
      }
    } finally {
      if (!_closing) emit(state.copyWith(busy: false, submitting: false));
    }
  }

  void cancelUpload() {
    if (_closing || !allowed || !state.submitting) return;
    _submissionCancelled = true;
    _repository.cancelSubmission();
  }

  Future<void> retryCleanup() async {
    if (_closing ||
        !allowed ||
        state.busy ||
        state.draft?.status != ScanDraftStatus.accepted) {
      return;
    }
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final draft = await _repository.retryCleanup();
      if (!_closing) emit(state.copyWith(draft: draft));
    } catch (error) {
      if (!_closing) emit(state.copyWith(error: _message(error)));
    } finally {
      if (!_closing) emit(state.copyWith(busy: false));
    }
  }

  Future<bool> discard() async {
    if (_closing ||
        !allowed ||
        state.busy ||
        state.draft?.status == ScanDraftStatus.accepted) {
      return false;
    }
    emit(state.copyWith(busy: true, clearError: true));
    _saveTimer?.cancel();
    _pendingProperties = null;
    try {
      await _saving;
      if (_closing) return false;
      if (_camera case final ScannerBatchCamera batch) {
        await batch.discardPendingPages();
        if (_closing) return false;
        emit(state.copyWith(pendingPages: 0, batchTotalPages: 0));
      }
      final capture = state.capture;
      if (capture != null) {
        await _camera.releaseCapture(capture.id);
        if (_closing) return false;
        emit(state.copyWith(clearCapture: true, stage: ScannerStage.review));
      }
      await _repository.discard();
      if (_closing) return false;
      emit(ScannerState(loading: false, discarded: true));
      return true;
    } catch (error) {
      if (!_closing) emit(state.copyWith(busy: false, error: _message(error)));
      return false;
    }
  }

  void _notifyAccepted(ScanDraft draft) {
    if (!_closing &&
        !_acceptedNotified &&
        draft.status == ScanDraftStatus.accepted) {
      _acceptedNotified = true;
      onAccepted?.call();
    }
  }

  String _message(Object error) => error is ScanFailure
      ? error.message
      : 'The scan could not be completed. Your saved draft is retained. Please try again.';

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _saveTimer?.cancel();
    _pendingProperties = null;
    _camera.cancelNewOperations();
    _repository.cancelNewOperations();
    emit(ScannerState(loading: false));
    await _cameraSubscription.cancel();
    await super.close();
  }
}
