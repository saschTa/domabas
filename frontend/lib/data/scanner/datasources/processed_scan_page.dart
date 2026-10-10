import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../domain/scanner/models/scan.dart';
import '../models/scan_image_limits.dart';

Future<({int width, int height, Uint8List preview})> prepareProcessedScanPage(
  Uint8List bytes,
) => Isolate.run(() {
  final image = _decodePage(bytes);
  return (
    width: image.width,
    height: image.height,
    preview: _preview(image, 1200, ScanImageLimits.maxPreviewBytes),
  );
});

Future<Uint8List> createProcessedScanThumbnail(Uint8List bytes) => Isolate.run(
  () => _preview(_decodePage(bytes), 400, ScanImageLimits.maxThumbnailBytes),
);

img.Image _decodePage(Uint8List bytes) {
  final header = img.JpegDecoder().startDecode(bytes);
  if (header == null ||
      !ScanImageLimits.validDimensions(header.width, header.height)) {
    throw const ScanFailure(
      'Scanned pages must be JPEGs of at most 50 megapixels.',
    );
  }
  final image = img.decodeJpg(bytes);
  if (image == null) {
    throw const ScanFailure('The scanned page could not be read.');
  }
  return image;
}

Uint8List _preview(img.Image image, int longestSide, int limit) {
  final scale = math.min(
    1.0,
    longestSide / math.max(image.width, image.height),
  );
  final resized = img.copyResize(
    image,
    width: math.max(1, (image.width * scale).round()),
    height: math.max(1, (image.height * scale).round()),
    interpolation: img.Interpolation.average,
  );
  for (final quality in [85, 70, 55, 40]) {
    final bytes = img.encodeJpg(resized, quality: quality);
    if (bytes.length <= limit) return bytes;
  }
  throw const ScanFailure(
    'The scanned page preview exceeds its storage limit.',
  );
}
