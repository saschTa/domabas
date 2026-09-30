import 'dart:typed_data';

import '../../../domain/document/models/document_limits.dart';
import '../../../domain/document/models/document_upload.dart';

const documentUploadByteLimit = documentOriginalByteLimit;
const documentUploadReadChunk = 64 * 1024;
const documentUploadQueueLimit = 20;

final class DocumentUploadSelection {
  DocumentUploadSelection({
    Iterable<DocumentUploadCandidate> candidates = const [],
    this.cancelled = false,
    this.rejection,
  }) : candidates = List.unmodifiable(candidates);
  final List<DocumentUploadCandidate> candidates;
  final bool cancelled;
  final String? rejection;
}

final class DocumentUploadReadException implements Exception {
  const DocumentUploadReadException(this.message);
  final String message;
}

abstract interface class DocumentUploadHandle {
  String get displayName;
  Future<Uint8List> read(
    Future<void> cancel, {
    void Function(String)? onReadFailure,
  });
}

final class RejectedDocumentUploadHandle implements DocumentUploadHandle {
  const RejectedDocumentUploadHandle(this.displayName, this.message);
  @override
  final String displayName;
  final String message;
  @override
  Future<Uint8List> read(
    Future<void> cancel, {
    void Function(String)? onReadFailure,
  }) => Future.error(DocumentUploadReadException(message));
}

abstract class DocumentUploadAcquisition {
  final _handles = <String, DocumentUploadHandle>{};
  int _nextId = 0;
  bool _disposed = false;
  bool _reading = false;

  Future<DocumentUploadSelection> choose({required bool Function(int) reserve});

  DocumentUploadSelection captureNativePaths(
    List<String> paths, {
    required bool Function(int) reserve,
  });

  DocumentUploadSelection capture(
    int count, {
    required bool Function(int) reserve,
    required DocumentUploadHandle Function(int) handleAt,
  }) {
    if (_disposed) {
      return DocumentUploadSelection(
        rejection: 'This file selection has ended.',
      );
    }
    if (count == 0) {
      return DocumentUploadSelection(rejection: 'No files could be received.');
    }
    if (count > documentUploadQueueLimit ||
        _handles.length + count > documentUploadQueueLimit) {
      return DocumentUploadSelection(
        rejection: 'Select up to 20 files within the remaining upload places.',
      );
    }
    if (!reserve(count)) return DocumentUploadSelection();
    final candidates = <DocumentUploadCandidate>[];
    for (var index = 0; index < count; index++) {
      DocumentUploadHandle handle;
      try {
        handle = handleAt(index);
      } catch (_) {
        handle = const RejectedDocumentUploadHandle(
          'Document',
          'This file could not be received.',
        );
      }
      final id = 'upload-${++_nextId}';
      _handles[id] = handle;
      candidates.add(
        DocumentUploadCandidate(
          id: id,
          displayName: DocumentUploadNames.filename(handle.displayName),
        ),
      );
    }
    return DocumentUploadSelection(candidates: candidates);
  }

  Future<Uint8List> read(
    String id,
    Future<void> cancel, {
    void Function(String)? onReadFailure,
  }) async {
    final handle = _handles[id];
    if (handle == null || _disposed) {
      throw const DocumentUploadReadException('This file selection has ended.');
    }
    if (_reading) {
      throw const DocumentUploadReadException(
        'Finishing the previous file selection.',
      );
    }
    _reading = true;
    try {
      return await handle.read(cancel, onReadFailure: onReadFailure);
    } finally {
      _reading = false;
    }
  }

  void release(Iterable<String> ids) {
    for (final id in ids) {
      _handles.remove(id);
    }
  }

  void dispose() {
    _disposed = true;
    _handles.clear();
  }
}
