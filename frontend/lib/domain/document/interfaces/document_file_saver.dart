import 'dart:typed_data';

import '../models/document.dart';

abstract interface class DocumentFileSaver {
  Future<void> save(DocumentFile file, Uint8List bytes);
}
