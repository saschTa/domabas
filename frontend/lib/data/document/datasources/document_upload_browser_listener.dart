import 'document_upload_acquisition.dart';

final class DocumentUploadBrowserTarget {
  const DocumentUploadBrowserTarget({
    required this.acquisition,
    required this.canAdmit,
    required this.reserve,
    required this.onBatch,
    required this.onHover,
    required this.onRejected,
    this.rejectionReason,
  });
  final DocumentUploadAcquisition acquisition;
  final bool Function() canAdmit;
  final bool Function(int) reserve;
  final void Function(DocumentUploadSelection) onBatch;
  final void Function(bool) onHover;
  final void Function(String) onRejected;
  final String? Function()? rejectionReason;
}

abstract interface class DocumentUploadBrowserListener {
  void clearHover();
  void retireTarget();
  void dispose();
}
