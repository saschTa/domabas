import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../../../domain/document/interfaces/document_file_saver.dart';
import '../../../domain/document/models/document.dart';
import '../datasources/document_file_save_data_source.dart';

final class LocalDocumentFileSaver implements DocumentFileSaver {
  LocalDocumentFileSaver(this._source);

  final DocumentFileSaveDataSource _source;

  @override
  Future<void> save(DocumentFile file, Uint8List bytes) {
    var filename = path.posix
        .basename(file.originalFilename.replaceAll('\\', '/'))
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    if (filename.isEmpty || filename == '.' || filename == '..') {
      filename = 'document';
    }
    if (path.posix.extension(filename).isEmpty) {
      filename += switch (file.mediaType) {
        'application/pdf' => '.pdf',
        'image/png' => '.png',
        'image/jpeg' => '.jpg',
        'message/rfc822' => '.eml',
        _ => '.bin',
      };
    }
    return _source.save(
      filename: filename,
      mediaType: file.mediaType,
      bytes: bytes,
    );
  }
}
