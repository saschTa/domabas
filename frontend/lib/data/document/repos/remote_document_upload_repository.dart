import 'dart:async';

import '../../../domain/document/interfaces/document_upload_repository.dart';
import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_upload.dart';
import '../datasources/document_upload_acquisition.dart';
import '../datasources/document_upload_remote_data_source.dart';
import '../models/prepared_document_upload_metadata.dart';

final class RemoteDocumentUploadRepository implements DocumentUploadRepository {
  RemoteDocumentUploadRepository(this._acquisition, this._remote);
  final DocumentUploadAcquisition _acquisition;
  final DocumentUploadRemoteDataSource _remote;
  final _owned = <String>{};
  final _active = <Completer<void>>{};
  bool _disposed = false;

  @override
  Future<DocumentUploadResult> upload(
    DocumentUploadCandidate candidate, {
    required Future<void> cancel,
    required void Function() onSending,
    void Function(Document)? onAccepted,
    void Function(String)? onReadFailure,
  }) async {
    if (_disposed) {
      release([candidate.id]);
      return const DocumentUploadResult(
        outcome: DocumentUploadOutcome.rejected,
        message: 'This file selection has ended.',
      );
    }
    _owned.add(candidate.id);
    final stop = Completer<void>();
    _active.add(stop);
    unawaited(
      cancel.then((_) {
        if (!stop.isCompleted) stop.complete();
      }),
    );
    var sent = false;
    try {
      final bytes = await _acquisition.read(
        candidate.id,
        stop.future,
        onReadFailure: onReadFailure,
      );
      final filename = DocumentUploadNames.filename(candidate.displayName);
      final metadata = _remote.prepare(
        DocumentUploadNames.properties(filename),
      );
      final document = await _remote.sendOriginal(
        bytes,
        metadata,
        filename,
        stop.future,
        onSending: () {
          sent = true;
          try {
            onSending();
          } catch (_) {}
        },
      );
      final result = DocumentUploadResult(
        outcome: DocumentUploadOutcome.accepted,
        message: 'Accepted — processing continues.',
        document: document,
      );
      try {
        onAccepted?.call(document);
      } catch (_) {}
      return result;
    } on DocumentUploadReadException catch (error) {
      return DocumentUploadResult(
        outcome: DocumentUploadOutcome.rejected,
        message: error.message,
      );
    } on DocumentUploadException catch (error) {
      return DocumentUploadResult(
        outcome: switch (error.disposition) {
          DocumentUploadDisposition.rejected => DocumentUploadOutcome.rejected,
          DocumentUploadDisposition.duplicate =>
            DocumentUploadOutcome.duplicate,
          DocumentUploadDisposition.uncertain =>
            DocumentUploadOutcome.uncertain,
        },
        message: error.disposition == DocumentUploadDisposition.uncertain
            ? 'Upload outcome is unknown. Check the library before selecting this file again.'
            : error.message,
      );
    } catch (_) {
      return DocumentUploadResult(
        outcome: sent
            ? DocumentUploadOutcome.uncertain
            : DocumentUploadOutcome.rejected,
        message: sent
            ? 'Upload outcome is unknown. Check the library before selecting this file again.'
            : 'This file could not be read or prepared for upload.',
      );
    } finally {
      if (!stop.isCompleted) stop.complete();
      _active.remove(stop);
      release([candidate.id]);
    }
  }

  @override
  void release(Iterable<String> ids) {
    for (final id in ids) {
      _owned.remove(id);
      _acquisition.release([id]);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final stop in _active) {
      if (!stop.isCompleted) stop.complete();
    }
    _remote.cancelRequests();
  }
}
