import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'document_upload_acquisition.dart';

DocumentUploadAcquisition createDocumentUploadAcquisition() =>
    WebDocumentUploadAcquisition();

final class WebDocumentUploadAcquisition extends DocumentUploadAcquisition {
  WebDocumentUploadAcquisition({
    this.readTimeout = const Duration(seconds: 10),
  });
  final Duration readTimeout;
  bool _choosing = false;

  @override
  Future<DocumentUploadSelection> choose({
    required bool Function(int) reserve,
  }) {
    if (_choosing) {
      return Future.value(
        DocumentUploadSelection(
          rejection: 'Finishing the previous file selection.',
        ),
      );
    }
    _choosing = true;
    final completed = Completer<DocumentUploadSelection>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..multiple = true;
    input.style.display = 'none';
    input.setAttribute('aria-label', 'Upload PDF, PNG, JPEG or EML files');
    late final JSFunction changed, cancelled;
    void finish(DocumentUploadSelection selection) {
      if (completed.isCompleted) return;
      input.removeEventListener('change', changed);
      input.removeEventListener('cancel', cancelled);
      input.remove();
      _choosing = false;
      completed.complete(selection);
    }

    changed = ((web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) {
        finish(DocumentUploadSelection(cancelled: true));
        return;
      }
      try {
        finish(
          capture(
            files.length,
            reserve: reserve,
            handleAt: (index) {
              final file = files.item(index);
              return file == null
                  ? const RejectedDocumentUploadHandle(
                      'Document',
                      'This file could not be received.',
                    )
                  : _BrowserDocumentUploadHandle(file, readTimeout);
            },
          ),
        );
      } catch (_) {
        finish(
          DocumentUploadSelection(rejection: 'No files could be received.'),
        );
      }
    }).toJS;
    cancelled = ((web.Event _) => finish(
      DocumentUploadSelection(cancelled: true),
    )).toJS;
    input.addEventListener('change', changed);
    input.addEventListener('cancel', cancelled);
    web.document.body?.append(input);
    try {
      input.click();
    } catch (_) {
      finish(
        DocumentUploadSelection(
          rejection: 'The file chooser could not be opened.',
        ),
      );
    }
    return completed.future;
  }

  DocumentUploadSelection captureDrop(
    web.DataTransfer transfer, {
    required bool Function(int) reserve,
  }) {
    final items = transfer.items;
    var count = 0;
    for (var index = 0; index < items.length; index++) {
      if (items[index].kind == 'file') count++;
    }
    if (count == 0) {
      final files = transfer.files;
      return capture(
        files.length,
        reserve: reserve,
        handleAt: (index) {
          final file = files.item(index);
          return file == null
              ? const RejectedDocumentUploadHandle(
                  'Document',
                  'This file could not be received.',
                )
              : _BrowserDocumentUploadHandle(file, readTimeout);
        },
      );
    }
    var position = 0;
    return capture(
      count,
      reserve: reserve,
      handleAt: (_) {
        while (position < items.length && items[position].kind != 'file') {
          position++;
        }
        final item = items[position++];
        web.FileSystemEntry? entry;
        try {
          entry = item.webkitGetAsEntry();
        } catch (_) {}
        if (entry != null && entry.isDirectory) {
          return RejectedDocumentUploadHandle(
            entry.name,
            'Folders cannot be uploaded. Select individual files.',
          );
        }
        final file = item.getAsFile();
        return file == null
            ? RejectedDocumentUploadHandle(
                entry?.name ?? 'Document',
                'This file could not be received.',
              )
            : _BrowserDocumentUploadHandle(file, readTimeout);
      },
    );
  }

  @override
  DocumentUploadSelection captureNativePaths(
    List<String> paths, {
    required bool Function(int) reserve,
  }) => DocumentUploadSelection(
    rejection: 'Only browser-selected physical files can be uploaded.',
  );
}

final class _BrowserDocumentUploadHandle implements DocumentUploadHandle {
  const _BrowserDocumentUploadHandle(this.file, this.timeout);
  final web.File file;
  final Duration timeout;
  @override
  String get displayName => file.name;

  @override
  Future<Uint8List> read(
    Future<void> cancel, {
    void Function(String)? onReadFailure,
  }) async {
    final length = file.size;
    if (length == 0) {
      throw const DocumentUploadReadException(
        'Empty files cannot be uploaded.',
      );
    }
    if (length > documentUploadByteLimit) {
      throw const DocumentUploadReadException(
        'This file exceeds the 100 MiB limit.',
      );
    }
    final control = _BrowserDocumentUploadReadControl(
      cancel,
      timeout,
      onReadFailure,
    );
    try {
      await Future<void>.value();
      control.check();
      final bytes = Uint8List(length);
      var offset = 0;
      while (offset < length) {
        final end = (offset + documentUploadReadChunk).clamp(0, length);
        final slice = await control.read(file.slice(offset, end));
        if (slice.length != end - offset) {
          throw const DocumentUploadReadException(
            'This file changed while it was being read.',
          );
        }
        bytes.setRange(offset, end, slice);
        offset = end;
      }
      control.check();
      if (file.size != length) {
        throw const DocumentUploadReadException(
          'This file changed while it was being read.',
        );
      }
      return bytes;
    } finally {
      control.dispose();
    }
  }
}

final class _BrowserDocumentUploadReadControl {
  _BrowserDocumentUploadReadControl(
    Future<void> cancel,
    this.timeout,
    this.onReadFailure,
  ) {
    unawaited(
      cancel.then((_) {
        if (_finished) return;
        _cancelled = true;
        _abort();
      }),
    );
  }
  final Duration timeout;
  final void Function(String)? onReadFailure;
  web.FileReader? _reader;
  bool _cancelled = false, _timedOut = false, _finished = false;
  void _abort() {
    final reader = _reader;
    if (reader != null && reader.readyState == web.FileReader.LOADING) {
      reader.abort();
    }
  }

  void check() {
    if (_cancelled) {
      throw const DocumentUploadReadException(
        'File reading was cancelled before uploading.',
      );
    }
    if (_timedOut) {
      throw const DocumentUploadReadException(
        'The file stopped responding while it was being read.',
      );
    }
  }

  Future<Uint8List> read(web.Blob blob) async {
    check();
    final reader = web.FileReader();
    _reader = reader;
    final finished = Completer<void>();
    final terminal = ((web.Event _) {
      if (!finished.isCompleted) finished.complete();
    }).toJS;
    reader.addEventListener('loadend', terminal);
    final timer = Timer(timeout, () {
      _timedOut = true;
      try {
        onReadFailure?.call(
          'The file stopped responding while it was being read.',
        );
      } catch (_) {}
      _abort();
    });
    try {
      reader.readAsArrayBuffer(blob);
      await finished.future;
      check();
      if (reader.error != null || reader.result == null) {
        throw const DocumentUploadReadException('This file could not be read.');
      }
      return (reader.result as JSArrayBuffer).toDart.asUint8List();
    } finally {
      timer.cancel();
      reader.removeEventListener('loadend', terminal);
      _reader = null;
    }
  }

  void dispose() {
    _finished = true;
    _reader = null;
  }
}
