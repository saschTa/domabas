import 'dart:typed_data';

import '../domain/document/models/document.dart';
import '../data/document/datasources/document_upload_remote_data_source.dart';
import '../data/document/models/prepared_document_upload_metadata.dart';
import '../data/scanner/repos/scan_upload_data_port.dart';

final class ScannerDocumentUploadAdapter implements ScanUploadDataPort {
  ScannerDocumentUploadAdapter(this.source);
  final DocumentUploadRemoteDataSource source;
  @override
  PreparedDocumentUploadMetadata prepare(DocumentProperties properties) =>
      source.prepare(properties);
  @override
  Future<Document> send(
    Uint8List pdfBytes,
    PreparedDocumentUploadMetadata metadata,
    String filename,
    Future<void> cancel,
  ) => source.send(pdfBytes, metadata, filename, cancel);
}
