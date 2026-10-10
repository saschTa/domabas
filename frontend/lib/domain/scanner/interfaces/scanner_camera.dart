import '../models/scan.dart';

abstract interface class ScannerCamera {
  bool get usesSystemCapture;
  ScanCameraState get state;
  Stream<ScanCameraState> get states;
  Future<void> start();
  Future<void> suspend();
  Future<ScanCapture> capture();
  Future<void> releaseCapture(String id);
  void cancelNewOperations();
  Future<void> close();
}

abstract interface class ScannerSystemCapture {
  String get systemCaptureNotice;
}

abstract interface class ScannerBatchCamera {
  int get pendingPageCount;
  Future<void> beginBatch({required int maxPages});
  Future<ScanCapture> captureNextPage();
  Future<void> acknowledgePage(String id);
  Future<void> discardPendingPages();
}
