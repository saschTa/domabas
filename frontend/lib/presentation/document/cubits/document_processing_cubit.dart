import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/document/interfaces/document_processing_repository.dart';
import '../../../domain/document/models/document_processing.dart';

final class DocumentProcessingState {
  DocumentProcessingState({
    this.pipeline,
    Map<(String, String), int>? counts,
    this.countsRefreshing = false,
    this.countsError = false,
    Iterable<DocumentProcessingJob> jobs = const [],
    Iterable<DocumentReindexBatch> batches = const [],
    this.selected,
    this.status,
    this.jobPipeline,
    this.nextCursor,
    this.batchCursor,
    this.loading = false,
    this.saving = false,
    this.detailLoading = false,
    this.browsingHistory = false,
    this.error,
    this.notice,
    this.pendingRequest,
  }) : counts = counts == null ? null : Map.unmodifiable(counts),
       jobs = List.unmodifiable(jobs),
       batches = List.unmodifiable(batches);
  final Map<(String, String), int>? counts;
  final bool countsRefreshing, countsError;
  final DocumentProcessingPipeline? pipeline;
  final List<DocumentProcessingJob> jobs;
  final List<DocumentReindexBatch> batches;
  final DocumentProcessingJob? selected;
  final String? status, nextCursor, batchCursor, error, notice;
  final String? jobPipeline;
  final bool loading, saving, detailLoading, browsingHistory;
  final DocumentReindexRequest? pendingRequest;
}

final class DocumentProcessingCubit extends Cubit<DocumentProcessingState> {
  DocumentProcessingCubit(
    this._repository, {
    required this.canReadJobs,
    required this.canReindex,
    String Function()? requestId,
  }) : _requestId = requestId ?? processingRequestId,
       super(DocumentProcessingState());
  final DocumentProcessingRepository _repository;
  final bool canReadJobs, canReindex;
  final String Function() _requestId;
  bool _active = false,
      _loading = false,
      _saving = false,
      _detailLoading = false;
  bool _olderJobs = false, _olderBatches = false;
  bool _polling = false;
  int _epoch = 0, _reads = 0, _details = 0;
  late final _refresh = AutomaticRefresh(
    read: () => load(poll: true),
    busy: () => _loading || _saving || _detailLoading,
    interval: () => Duration(seconds: _error == null ? 1 : 30),
  );
  void invalidate() => _refresh.invalidate();

  Completer<void>? _readCancel, _writeCancel, _detailCancel;
  Map<(String, String), int>? _counts;
  bool _countsError = false;
  DocumentProcessingPipeline? _pipeline;
  List<DocumentProcessingJob> _jobs = const [];
  List<DocumentReindexBatch> _batches = const [];
  DocumentProcessingJob? _selected;
  String? _status, _cursor, _batchCursor, _error, _notice;
  String? _jobPipeline;
  DocumentReindexRequest? _pending;
  bool get active => _active && !isClosed;
  bool get _blockingRead => _loading && (!_polling || _pipeline == null);
  bool get canRequest =>
      active &&
      canReindex &&
      _pipeline != null &&
      !_blockingRead &&
      !_saving &&
      _pending == null;

  void setActive(bool value) {
    if (isClosed || value == _active) return;
    _active = value;
    _refresh.setActive(value);
    _epoch++;
    _cancel(_readCancel);
    _cancel(_detailCancel);
    _cancel(_writeCancel);
    _loading = _saving = _detailLoading = false;
    _publish();
    if (value && (canReadJobs || canReindex)) unawaited(load(poll: true));
  }

  void filter(String? value, {String? pipeline}) {
    if (isClosed ||
        !canReadJobs ||
        (value == _status && pipeline == _jobPipeline)) {
      return;
    }
    _status = value;
    _jobPipeline = pipeline;
    _jobs = const [];
    _cursor = null;
    _olderJobs = false;
    _cancel(_readCancel);
    _reads++;
    _loading = false;
    _publish();
    if (_saving) {
      _refresh.invalidate();
    } else if (active) {
      unawaited(load());
    }
  }

  Future<void> load({
    bool moreJobs = false,
    bool moreBatches = false,
    bool poll = false,
  }) async {
    if (!poll) _cancelBackgroundRead();
    if (!active || _loading || _saving || (!canReadJobs && !canReindex)) return;
    if ((moreJobs && _cursor == null) ||
        (moreBatches && _batchCursor == null)) {
      return;
    }
    _loading = true;
    _polling = poll;
    if (!poll) _error = null;
    final epoch = _epoch, read = ++_reads;
    final cancel = _readCancel = Completer<void>();
    _publish();
    try {
      final pipeline = await _repository.getNamespacePipeline(
        cancel: cancel.future,
      );
      if (!_current(epoch) || read != _reads) return;
      final jobs = canReadJobs && !moreBatches
          ? await _repository.listJobs(
              status: _status,
              pipeline: _jobPipeline,
              cursor: moreJobs ? _cursor : null,
              cancel: cancel.future,
            )
          : null;
      final batches = moreJobs
          ? null
          : await _repository.listNamespaceBatches(
              cursor: moreBatches ? _batchCursor : null,
              cancel: cancel.future,
            );
      final jobUpdates = <DocumentProcessingJob>[];
      final batchUpdates = <DocumentReindexBatch>[];
      final selectedId = _selected?.id;
      final detail = _details;
      if (poll && _olderJobs) {
        final candidates = _jobs
            .where((job) => job.active && job.id != selectedId)
            .toList();
        for (final job in candidates) {
          jobUpdates.add(
            await _repository.getJob(job.id, cancel: cancel.future),
          );
        }
      }
      if (poll && _olderBatches) {
        final candidates = _batches.where((batch) => batch.active).toList();
        for (final batch in candidates) {
          batchUpdates.add(
            await _repository.getNamespaceBatch(
              batch.id,
              cancel: cancel.future,
            ),
          );
        }
      }
      final selected = selectedId != null && !_detailLoading
          ? await _repository.getJob(selectedId, cancel: cancel.future)
          : null;
      if (!_current(epoch) || read != _reads) return;
      _error = null;
      _pipeline = pipeline;
      if (jobs != null) {
        _counts = jobs.counts;
        _countsError = false;
        if (poll && _olderJobs) {
          _jobs = _replace(_jobs, [...jobs.items, ...jobUpdates], (v) => v.id);
        } else {
          _jobs = _merge(moreJobs ? _jobs : const [], jobs.items, (v) => v.id);
          _cursor = jobs.nextCursor;
          _olderJobs = moreJobs;
        }
      }
      if (batches != null) {
        if (poll && _olderBatches) {
          _batches = _replace(_batches, [
            ...batches.items,
            ...batchUpdates,
          ], (v) => v.id);
        } else {
          _batches = _merge(
            moreBatches ? _batches : const [],
            batches.items,
            (v) => v.id,
          );
          _batchCursor = batches.nextCursor;
          _olderBatches = moreBatches;
        }
      }
      final pending = _pending;
      if (pending != null && _batches.any((b) => b.id == pending.id)) {
        _pending = null;
        _notice = 'Reindex request accepted. Progress is shown below.';
      }
      if (selected != null &&
          detail == _details &&
          _selected?.id == selected.id) {
        _selected = selected;
        _jobs = _replace(_jobs, [selected], (v) => v.id);
      }
      if (_status != null) {
        _jobs = _jobs.where((job) => job.status == _status).toList();
      }
      if (_jobPipeline != null) {
        _jobs = _jobs.where((job) => job.pipeline == _jobPipeline).toList();
      }
    } on DocumentProcessingFailure catch (failure) {
      if (_current(epoch) &&
          read == _reads &&
          failure.kind != DocumentProcessingFailureKind.cancelled) {
        _error = failure.message;
        _countsError = true;
      }
    } finally {
      if (_current(epoch) && read == _reads) {
        _loading = false;
        _publish();
      }
    }
  }

  Future<void> selectJob(String id) async {
    if (!active || !canReadJobs) return;
    _cancel(_detailCancel);
    final cancel = _detailCancel = Completer<void>();
    final epoch = _epoch, detail = ++_details;
    _detailLoading = true;
    _error = null;
    _publish();
    try {
      final job = await _repository.getJob(id, cancel: cancel.future);
      if (_current(epoch) && detail == _details) _selected = job;
    } on DocumentProcessingFailure catch (failure) {
      if (_current(epoch) &&
          detail == _details &&
          failure.kind != DocumentProcessingFailureKind.cancelled) {
        _error = failure.message;
      }
    } finally {
      if (_current(epoch) && detail == _details) {
        _detailLoading = false;
        _publish();
      }
    }
  }

  void clearSelection() {
    _cancel(_detailCancel);
    _details++;
    _selected = null;
    _detailLoading = false;
    _publish();
  }

  Future<void> requestReindex({bool retry = false}) async {
    if (!active ||
        !canReindex ||
        _saving ||
        _blockingRead ||
        _pipeline == null ||
        (retry ? _pending == null : !canRequest)) {
      return;
    }
    _cancelBackgroundRead();
    final request =
        _pending ??
        DocumentReindexRequest(_requestId(), _pipeline!.configuration.revision);
    _pending = request;
    _saving = true;
    _error = null;
    _notice = null;
    final epoch = _epoch, cancel = _writeCancel = Completer<void>();
    _publish();
    try {
      final batch = await _repository.createNamespaceBatch(
        request,
        cancel: cancel.future,
      );
      if (!_current(epoch)) return;
      _pending = null;
      _batches = _merge([batch], _batches, (v) => v.id);
      _notice = 'Reindex request accepted. Originals will be processed in the background.';
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
      emit(
        DocumentProcessingState(
          pipeline: _pipeline,
          counts: _counts,
          countsRefreshing: _loading,
          countsError: _countsError,
          jobs: _jobs,
          batches: _batches,
          selected: _selected,
          status: _status,
          jobPipeline: _jobPipeline,
          nextCursor: _cursor,
          batchCursor: _batchCursor,
          loading: _blockingRead,
          saving: _saving,
          detailLoading: _detailLoading,
          browsingHistory: _olderJobs || _olderBatches,
          error: _error,
          notice: _notice,
          pendingRequest: _pending,
        ),
      );
    }
  }

  static void _cancel(Completer<void>? value) {
    if (value != null && !value.isCompleted) value.complete();
  }

  static List<T> _merge<T>(
    List<T> first,
    List<T> second,
    String Function(T) id,
  ) {
    final seen = <String>{};
    return List.unmodifiable(
      [...first, ...second].where((v) => seen.add(id(v))),
    );
  }

  static List<T> _replace<T>(
    List<T> current,
    List<T> updates,
    String Function(T) id,
  ) {
    final byId = {for (final update in updates) id(update): update};
    return List.unmodifiable(current.map((value) => byId[id(value)] ?? value));
  }

  @override
  Future<void> close() {
    _refresh.dispose();
    setActive(false);
    return super.close();
  }
}
