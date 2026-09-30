import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/document/interfaces/document_upload_repository.dart';
import '../../../domain/document/interfaces/document_upload_scheduler.dart';
import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_upload.dart';

enum DocumentUploadPhase {
  waiting,
  reading,
  uploading,
  accepted,
  rejected,
  duplicate,
  uncertain,
}

final class DocumentUploadRow {
  const DocumentUploadRow({
    required this.candidate,
    required this.phase,
    this.message = '',
  });
  final DocumentUploadCandidate candidate;
  final DocumentUploadPhase phase;
  final String message;
  bool get pending => const {
    DocumentUploadPhase.waiting,
    DocumentUploadPhase.reading,
    DocumentUploadPhase.uploading,
  }.contains(phase);
  String get label => switch (phase) {
    DocumentUploadPhase.waiting => 'Waiting',
    DocumentUploadPhase.reading => 'Reading file',
    DocumentUploadPhase.uploading => 'Uploading',
    DocumentUploadPhase.accepted => 'Accepted — processing continues',
    DocumentUploadPhase.rejected => 'Not uploaded',
    DocumentUploadPhase.duplicate => 'Already in this library',
    DocumentUploadPhase.uncertain => 'Outcome unknown',
  };
}

final class DocumentUploadsState {
  DocumentUploadsState({
    Iterable<DocumentUploadRow> rows = const [],
    this.hover = false,
    this.feedback = '',
    this.showFeedback = false,
    this.usable = false,
  }) : rows = List.unmodifiable(rows);
  final List<DocumentUploadRow> rows;
  final bool hover;
  final String feedback;
  final bool showFeedback;
  final bool usable;
  int get pending => rows.where((row) => row.pending).length;
  int get accepted =>
      rows.where((row) => row.phase == DocumentUploadPhase.accepted).length;
}

final class DocumentUploadsCubit extends Cubit<DocumentUploadsState> {
  DocumentUploadsCubit({
    required this.repository,
    required this.scheduler,
    required this.libraryName,
    required this.canRead,
    required this._allowed,
  }) : super(DocumentUploadsState()) {
    _schedulerSubscription = scheduler.changes.listen((_) => _pump());
  }
  final DocumentUploadRepository repository;
  final DocumentUploadScheduler scheduler;
  final String libraryName;
  final bool canRead;
  final bool _allowed;
  late final StreamSubscription<void> _schedulerSubscription;
  void Function()? onAccepted;
  void Function()? onGateChanged;
  bool _busy = false;
  bool _visible = true;
  bool _retired = false;
  bool _deferredInvalidation = false;
  int _generation = 0;
  int _reserved = 0;
  String? _activeId;
  Completer<void>? _cancel;
  Timer? _feedbackTimer;
  Duration _feedbackRemaining = const Duration(seconds: 8);
  DateTime? _feedbackStarted;
  bool get admissionAllowed => _allowed && !_busy && !_retired && _visible;
  bool get scopeUsable => _allowed && !_busy && !_retired;
  bool get visible => _visible;
  int get generation => _generation;
  int get freePlaces => 20 - state.pending - _reserved;

  void setGate({required bool busy, required bool visible}) {
    if (_retired) return;
    final changedBusy = _busy != busy;
    if (!_busy && busy) _cancelGeneration();
    _busy = busy;
    if (_visible != visible) {
      _pauseFeedback();
      _visible = visible;
      if (_visible) _scheduleFeedback();
    }
    _publish(hover: admissionAllowed ? state.hover : false);
    if (changedBusy) onGateChanged?.call();
    if (scopeUsable && _deferredInvalidation) {
      _deferredInvalidation = false;
      onAccepted?.call();
    }
    _pump();
  }

  bool reserveBatch(int count, {bool chooserResult = false}) {
    if (!(chooserResult ? scopeUsable : admissionAllowed)) return false;
    if (count == 0) {
      reject('No files could be received.');
      return false;
    }
    if (count > 20 || count > freePlaces) {
      reject(
        'This batch has $count files; $freePlaces places are available. None of this batch were uploaded.',
      );
      return false;
    }
    _reserved += count;
    return true;
  }

  void releaseReservation(int count) {
    _reserved = (_reserved - count).clamp(0, 20);
  }

  void receiveBatch(List<DocumentUploadCandidate> candidates) {
    releaseReservation(candidates.length);
    if (!scopeUsable) {
      repository.release(candidates.map((value) => value.id));
      return;
    }
    final rows = [
      ...state.rows,
      ...candidates.map(
        (value) => DocumentUploadRow(
          candidate: value,
          phase: DocumentUploadPhase.waiting,
        ),
      ),
    ];
    _publish(rows: rows);
    _announce(
      '${candidates.length} ${candidates.length == 1 ? 'file' : 'files'} queued for $libraryName.',
    );
    _pump();
  }

  void setHover(bool value) => _publish(hover: value && admissionAllowed);
  void reject(String message) {
    if (!_retired) {
      _publish(hover: false);
      _announce(message);
    }
  }

  void clearFinished() => _publish(
    rows: state.rows
        .where((row) => row.pending || row.candidate.id == _activeId)
        .toList(),
  );

  void _pump() {
    if (!admissionAllowed || _activeId != null || scheduler.contentBusy) return;
    final next = state.rows
        .where((row) => row.phase == DocumentUploadPhase.waiting)
        .firstOrNull;
    if (next == null) return;
    scheduler.start(() => _run(next.candidate));
  }

  Future<void> _run(DocumentUploadCandidate candidate) async {
    if (!admissionAllowed) return;
    final generation = _generation;
    final cancel = Completer<void>();
    _cancel = cancel;
    _activeId = candidate.id;
    _replace(candidate.id, DocumentUploadPhase.reading, '');
    _announce(
      'Reading ${candidate.displayName}. ${state.pending} files pending.',
    );
    try {
      final result = await repository.upload(
        candidate,
        cancel: cancel.future,
        onSending: () {
          if (!_retired && generation == _generation) {
            _replace(candidate.id, DocumentUploadPhase.uploading, '');
            _announce(
              'Uploading ${candidate.displayName}. ${state.pending} files pending.',
            );
          }
        },
        onAccepted: (document) => _accepted(candidate.id, document),
        onReadFailure: (message) {
          if (!_retired &&
              generation == _generation &&
              !_isAccepted(candidate.id)) {
            _replace(candidate.id, DocumentUploadPhase.rejected, message);
            _announce(_summary());
          }
        },
      );
      if (!_retired &&
          generation == _generation &&
          !_isAccepted(candidate.id)) {
        _replace(candidate.id, switch (result.outcome) {
          DocumentUploadOutcome.accepted => DocumentUploadPhase.accepted,
          DocumentUploadOutcome.rejected => DocumentUploadPhase.rejected,
          DocumentUploadOutcome.duplicate => DocumentUploadPhase.duplicate,
          DocumentUploadOutcome.uncertain => DocumentUploadPhase.uncertain,
        }, result.message);
        _announce(_summary());
      }
    } catch (_) {
      if (!_retired &&
          generation == _generation &&
          !_isAccepted(candidate.id)) {
        _replace(
          candidate.id,
          DocumentUploadPhase.uncertain,
          'Check the library before selecting this file again.',
        );
        _announce(_summary());
      }
    } finally {
      repository.release([candidate.id]);
      _activeId = null;
      _cancel = null;
    }
  }

  bool _isAccepted(String id) => state.rows.any(
    (row) =>
        row.candidate.id == id && row.phase == DocumentUploadPhase.accepted,
  );

  void _accepted(String id, Document document) {
    if (_retired || _isAccepted(id)) return;
    _replace(
      id,
      DocumentUploadPhase.accepted,
      'The server accepted this original. Processing continues.',
    );
    _announce(_summary());
    if (canRead) {
      if (scopeUsable) {
        onAccepted?.call();
      } else {
        _deferredInvalidation = true;
      }
    }
  }

  String _summary() {
    final rejected = state.rows
        .where((row) => row.phase == DocumentUploadPhase.rejected)
        .length;
    final uncertain = state.rows
        .where((row) => row.phase == DocumentUploadPhase.uncertain)
        .length;
    final duplicate = state.rows
        .where((row) => row.phase == DocumentUploadPhase.duplicate)
        .length;
    return 'Uploads: ${state.accepted} accepted, ${state.pending} pending, $rejected not uploaded, $duplicate already present, $uncertain unknown.';
  }

  void _replace(String id, DocumentUploadPhase phase, String message) {
    _publish(
      rows: state.rows
          .map(
            (row) => row.candidate.id == id
                ? DocumentUploadRow(
                    candidate: row.candidate,
                    phase: phase,
                    message: message,
                  )
                : row,
          )
          .toList(),
    );
  }

  void _announce(String message) {
    _feedbackTimer?.cancel();
    _feedbackStarted = null;
    _feedbackRemaining = const Duration(seconds: 8);
    _publish(feedback: message, showFeedback: true);
    _scheduleFeedback();
  }

  void _pauseFeedback() {
    if (_feedbackStarted case final started?) {
      _feedbackRemaining -= DateTime.now().difference(started);
      if (_feedbackRemaining.isNegative) _feedbackRemaining = Duration.zero;
    }
    _feedbackStarted = null;
    _feedbackTimer?.cancel();
  }

  void _scheduleFeedback() {
    if (!_visible || _retired || !state.showFeedback || state.pending > 0) {
      return;
    }
    _feedbackStarted = DateTime.now();
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(_feedbackRemaining, () {
      if (!_retired) _publish(showFeedback: false);
    });
  }

  void _publish({
    List<DocumentUploadRow>? rows,
    bool? hover,
    String? feedback,
    bool? showFeedback,
  }) {
    if (isClosed || _retired) return;
    var values = rows ?? state.rows;
    var finished = values.where((row) => !row.pending).length;
    if (finished > 40) {
      values = values.where((row) {
        if (!row.pending && row.candidate.id != _activeId && finished > 40) {
          finished--;
          return false;
        }
        return true;
      }).toList();
    }
    emit(
      DocumentUploadsState(
        rows: values,
        hover: hover ?? state.hover,
        feedback: feedback ?? state.feedback,
        showFeedback: showFeedback ?? state.showFeedback,
        usable: admissionAllowed,
      ),
    );
  }

  void _cancelGeneration() {
    _generation++;
    _reserved = 0;
    if (_cancel case final cancel?) {
      if (!cancel.isCompleted) cancel.complete();
    }
    final queued = state.rows
        .where((row) => row.phase == DocumentUploadPhase.waiting)
        .map((row) => row.candidate.id)
        .toList();
    repository.release(queued);
    _publish(
      hover: false,
      rows: state.rows
          .map(
            (row) => row.pending
                ? DocumentUploadRow(
                    candidate: row.candidate,
                    phase: row.phase == DocumentUploadPhase.uploading
                        ? DocumentUploadPhase.uncertain
                        : DocumentUploadPhase.rejected,
                    message: row.phase == DocumentUploadPhase.uploading
                        ? 'Outcome unknown. Check the library before selecting this file again.'
                        : 'Cancelled before uploading.',
                  )
                : row,
          )
          .toList(),
    );
    _announce(_summary());
  }

  void retire() {
    if (_retired) return;
    _cancelGeneration();
    _retired = true;
    _feedbackTimer?.cancel();
    onGateChanged?.call();
    onAccepted = null;
    repository.dispose();
  }

  @override
  Future<void> close() async {
    retire();
    await _schedulerSubscription.cancel();
    return super.close();
  }
}
