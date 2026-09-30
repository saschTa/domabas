import '../models/document.dart';
import '../models/document_upload.dart';

abstract interface class DocumentUploadRepository {
  Future<DocumentUploadResult> upload(
    DocumentUploadCandidate candidate, {
    required Future<void> cancel,
    required void Function() onSending,
    void Function(Document)? onAccepted,
    void Function(String)? onReadFailure,
  });
  void release(Iterable<String> ids);
  void dispose();
}
