import 'dart:typed_data';

import '../../../domain/document/models/document.dart';
import '../../document/models/prepared_document_upload_metadata.dart';

abstract interface class ScanUploadDataPort {
  PreparedDocumentUploadMetadata prepare(DocumentProperties properties);
  Future<Document> send(
    Uint8List pdfBytes,
    PreparedDocumentUploadMetadata metadata,
    String filename,
    Future<void> cancel,
  );
}
