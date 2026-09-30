import 'dart:typed_data';

final class CorrectedScanPage {
  const CorrectedScanPage(this.bytes, this.thumbnail, this.width, this.height);
  final Uint8List bytes;
  final Uint8List thumbnail;
  final int width;
  final int height;
}
