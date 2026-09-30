import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

final class DocumentFileSaveDataSource {
  Future<void> save({
    required String filename,
    required String mediaType,
    required Uint8List bytes,
  }) async {
    await FilePicker.saveFile(
      fileName: filename,
      mimeType: mediaType,
      bytes: Uint8List.fromList(bytes),
      dialogTitle: 'Download original',
    );
  }
}
