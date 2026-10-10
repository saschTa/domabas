import '../../../domain/scanner/interfaces/scanner_camera.dart';
import '../../../domain/scanner/models/scan.dart';
import '../models/scan_assets.dart';

abstract interface class ScanCaptureDataPort implements ScannerCamera {
  Future<CorrectedScanPage> correct(ScanCapture capture, ScanCorners corners);
}
