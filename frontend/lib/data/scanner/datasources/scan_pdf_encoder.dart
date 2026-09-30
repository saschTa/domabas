import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'scan_pdf_document.dart';

final class ScanPdfPage {
  const ScanPdfPage(this.path, this.width, this.height);
  final String path;
  final int width, height;
}

final class ScanPdfEncoder {
  Future<Uint8List> encode(List<ScanPdfPage> pages) => Isolate.run(() async {
    final images = <ScanPdfImage>[];
    for (final page in pages) {
      images.add(
        ScanPdfImage(
          await File(page.path).readAsBytes(),
          page.width,
          page.height,
        ),
      );
    }
    return encodeScanPdf(images);
  });
}
