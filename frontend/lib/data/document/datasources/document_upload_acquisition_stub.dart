import 'document_upload_acquisition.dart';

DocumentUploadAcquisition createDocumentUploadAcquisition() =>
    _UnavailableDocumentUploadAcquisition();

final class _UnavailableDocumentUploadAcquisition
    extends DocumentUploadAcquisition {
  @override
  Future<DocumentUploadSelection> choose({
    required bool Function(int) reserve,
  }) => Future.value(
    DocumentUploadSelection(rejection: 'File selection is unavailable.'),
  );
  @override
  DocumentUploadSelection captureNativePaths(
    List<String> paths, {
    required bool Function(int) reserve,
  }) => DocumentUploadSelection(rejection: 'File selection is unavailable.');
}
