import '../../document/models/document.dart';
import '../models/scan.dart';

abstract interface class ScanDraftRepository {
  Future<ScanDraft> restore();
  Future<ScanDraft> saveProperties(DocumentProperties rawDraft);
  Future<ScanDraft> keepPage(ScanCapture capture, ScanCorners corners);
  Future<ScanDraft> removePage(String id);
  Future<ScanDraft> movePage(String id, int finalIndex);
  Future<ScanSubmission> submit();
  Future<ScanSubmission> retryUpload();
  Future<ScanDraft> retryCleanup();
  Future<void> discard();
  void cancelSubmission();
  void cancelNewOperations();
  Future<void> close();
}
