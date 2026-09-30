import '../models/scan.dart';

abstract interface class ScannerCamera {
  ScanCameraState get state;
  Stream<ScanCameraState> get states;
  Future<void> start();
  Future<void> suspend();
  Future<ScanCapture> capture();
  Future<void> releaseCapture(String id);
  void cancelNewOperations();
  Future<void> close();
}
