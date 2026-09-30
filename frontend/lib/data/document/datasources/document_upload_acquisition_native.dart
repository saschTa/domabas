import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

import '../../../domain/document/models/document_upload_validation.dart';
import 'document_upload_acquisition.dart';

DocumentUploadAcquisition createDocumentUploadAcquisition() =>
    NativeDocumentUploadAcquisition();

final class NativeDocumentUploadAcquisition extends DocumentUploadAcquisition {
  NativeDocumentUploadAcquisition({
    Future<List<PlatformFile>> Function()? picker,
    NativeDocumentUploadFiles? files,
    this.readTimeout = const Duration(seconds: 10),
  }) : _picker = picker ?? _choose,
       _files = files ?? _LocalDocumentUploadFiles();
  final Future<List<PlatformFile>> Function() _picker;
  final NativeDocumentUploadFiles _files;
  final Duration readTimeout;

  static Future<List<PlatformFile>> _choose() => FilePicker.pickFiles(
    dialogTitle: 'Upload PDF, PNG, JPEG or EML files',
    type: FileType.any,
    compressionQuality: 0,
    darwinOptions: const DarwinOptions(
      assetRepresentationMode: DarwinAssetRepresentationMode.current,
    ),
  );

  @override
  Future<DocumentUploadSelection> choose({
    required bool Function(int) reserve,
  }) {
    final pending = _picker();
    return pending.then((files) {
      if (files.isEmpty) return DocumentUploadSelection(cancelled: true);
      return capture(
        files.length,
        reserve: reserve,
        handleAt: (index) {
          final file = files[index];
          final location = file.path;
          if (location == null) {
            return RejectedDocumentUploadHandle(
              file.name,
              'Only local physical files can be uploaded.',
            );
          }
          return _NativeDocumentUploadHandle(
            location,
            file.name,
            readTimeout,
            _files,
          );
        },
      );
    });
  }

  @override
  DocumentUploadSelection captureNativePaths(
    List<String> paths, {
    required bool Function(int) reserve,
  }) => capture(
    paths.length,
    reserve: reserve,
    handleAt: (index) {
      final location = paths[index];
      return _NativeDocumentUploadHandle(
        location,
        path.basename(location),
        readTimeout,
        _files,
      );
    },
  );
}

abstract interface class NativeDocumentUploadFiles {
  Future<FileSystemEntityType> typeWithoutFollowingLinks(String location);
  Future<NativeDocumentUploadFile> open(String location);
}

abstract interface class NativeDocumentUploadFile {
  Future<int> length();
  Future<int> readInto(Uint8List buffer, int start, int end);
  Future<void> close();
}

final class _LocalDocumentUploadFiles implements NativeDocumentUploadFiles {
  @override
  Future<FileSystemEntityType> typeWithoutFollowingLinks(
    String location,
  ) async {
    final type = await FileSystemEntity.type(location, followLinks: false);
    if (type != FileSystemEntityType.file || Platform.isWindows) return type;
    final stat = await FileStat.stat(location);
    if ((stat.mode & 0xf000) != 0x8000) return FileSystemEntityType.notFound;
    return FileSystemEntity.type(location, followLinks: false);
  }

  @override
  Future<NativeDocumentUploadFile> open(String location) async =>
      _LocalDocumentUploadFile(await File(location).open(mode: FileMode.read));
}

final class _LocalDocumentUploadFile implements NativeDocumentUploadFile {
  _LocalDocumentUploadFile(this._file);
  final RandomAccessFile _file;
  @override
  Future<int> length() => _file.length();
  @override
  Future<int> readInto(Uint8List buffer, int start, int end) =>
      _file.readInto(buffer, start, end);
  @override
  Future<void> close() async {
    await _file.close();
  }
}

final class _NativeDocumentUploadHandle implements DocumentUploadHandle {
  const _NativeDocumentUploadHandle(
    this.location,
    this.displayName,
    this.timeout,
    this.files,
  );
  final String location;
  @override
  final String displayName;
  final Duration timeout;
  final NativeDocumentUploadFiles files;

  @override
  Future<Uint8List> read(
    Future<void> cancel, {
    void Function(String)? onReadFailure,
  }) async {
    if (location.isEmpty ||
        location.length > 32768 ||
        location.contains('\u0000') ||
        !DocumentUploadValidation.validScalars(location) ||
        !path.isAbsolute(location) ||
        Platform.isWindows && _windowsDevice(location) ||
        Platform.isWindows &&
            !RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)')
                .hasMatch(location)) {
      throw const DocumentUploadReadException(
        'Only absolute local file paths can be uploaded.',
      );
    }
    final control = _DocumentUploadReadControl(cancel, timeout, onReadFailure);
    NativeDocumentUploadFile? opened;
    try {
      await Future<void>.value();
      control.check();
      final type = await files.typeWithoutFollowingLinks(location);
      control.progress();
      if (type != FileSystemEntityType.file) {
        throw DocumentUploadReadException(switch (type) {
          FileSystemEntityType.directory =>
            'Folders cannot be uploaded. Select individual files.',
          FileSystemEntityType.link =>
            'Symbolic links cannot be uploaded. Select the original file.',
          FileSystemEntityType.notFound => 'This file is no longer available.',
          _ => 'Only regular physical files can be uploaded.',
        });
      }
      opened = await files.open(location);
      control.progress();
      final length = await opened.length();
      control.progress();
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
      final bytes = Uint8List(length);
      var offset = 0;
      while (offset < length) {
        final end = (offset + documentUploadReadChunk).clamp(0, length);
        final read = await opened.readInto(bytes, offset, end);
        control.progress();
        if (read <= 0) {
          throw const DocumentUploadReadException(
            'This file changed while it was being read.',
          );
        }
        offset += read;
      }
      final extra = Uint8List(1);
      final tail = await opened.readInto(extra, 0, 1);
      control.progress();
      final finalLength = await opened.length();
      control.progress();
      if (tail != 0 || finalLength != length) {
        throw const DocumentUploadReadException(
          'This file changed while it was being read.',
        );
      }
      return bytes;
    } on DocumentUploadReadException {
      rethrow;
    } on FileSystemException {
      throw const DocumentUploadReadException(
        'This file could not be read. Check that it is available and readable.',
      );
    } finally {
      try {
        await opened?.close();
        control.check();
      } finally {
        control.dispose();
      }
    }
  }
}

bool _windowsDevice(String location) {
  final normalized = location.replaceAll('/', r'\').toUpperCase();
  if (normalized.startsWith(r'\\.\') ||
      normalized.startsWith(r'\\?\GLOBALROOT\') ||
      normalized.startsWith(r'\\?\PIPE\')) {
    return true;
  }
  final leaf = normalized.split(r'\').last.replaceFirst(RegExp(r'[. ]+$'), '');
  return RegExp(r'^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$')
      .hasMatch(leaf);
}

final class _DocumentUploadReadControl {
  _DocumentUploadReadControl(
    Future<void> cancel,
    this.timeout,
    this.onReadFailure,
  ) {
    unawaited(
      cancel.then((_) {
        if (!_finished) _cancelled = true;
      }),
    );
    _arm();
  }
  final Duration timeout;
  final void Function(String)? onReadFailure;
  Timer? _timer;
  bool _cancelled = false, _timedOut = false, _finished = false;
  void _arm() {
    _timer?.cancel();
    _timer = Timer(timeout, () {
      if (_cancelled || _finished) return;
      _timedOut = true;
      try {
        onReadFailure?.call(
          'The file stopped responding while it was being read.',
        );
      } catch (_) {}
    });
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

  void progress() {
    check();
    _arm();
  }

  void dispose() {
    _finished = true;
    _timer?.cancel();
  }
}
