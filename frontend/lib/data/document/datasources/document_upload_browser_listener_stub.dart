import 'document_upload_browser_listener.dart';

DocumentUploadBrowserListener createDocumentUploadBrowserListener({
  required DocumentUploadBrowserTarget? Function() currentTarget,
  void Function(bool)? onVisibilityChanged,
}) => _InactiveDocumentUploadBrowserListener();

final class _InactiveDocumentUploadBrowserListener
    implements DocumentUploadBrowserListener {
  @override
  void clearHover() {}
  @override
  void retireTarget() {}
  @override
  void dispose() {}
}
