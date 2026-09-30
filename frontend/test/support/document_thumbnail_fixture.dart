import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:image/image.dart' as img;

Uint8List documentThumbnailBytes(Uint8List original) {
  final image = img.decodeImage(original)!;
  final scale = math.min(1.0, math.min(256 / image.width, 360 / image.height));
  return img.encodeJpg(
    img.copyResize(
      image,
      width: math.max(1, (image.width * scale).round()),
      height: math.max(1, (image.height * scale).round()),
    ),
  );
}

DocumentThumbnail documentThumbnailFixture(
  Uint8List bytes, {
  String? sourceSha256,
}) {
  final image = img.JpegDecoder().startDecode(bytes)!;
  return DocumentThumbnail(
    sha256: sha256.convert(bytes).toString(),
    sourceSha256: sourceSha256 ?? 'a' * 64,
    rendererRevision: 1,
    mediaType: 'image/jpeg',
    width: image.width,
    height: image.height,
    size: bytes.length,
  );
}
