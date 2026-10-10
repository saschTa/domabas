import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../domain/scanner/models/scan.dart';
import '../models/scan_image_limits.dart';

final class ScanPdfImage {
  const ScanPdfImage(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width, height;
}

Future<Uint8List> encodeScanPdf(List<ScanPdfImage> pages) async {
  if (pages.isEmpty || pages.length > 20) {
    throw const ScanFailure('A PDF must contain between one and 20 pages.');
  }
  final pdf = pw.Document(compress: false);
  for (final page in pages) {
    if (!ScanImageLimits.validDimensions(page.width, page.height)) {
      throw const ScanFailure('Invalid PDF page dimensions.');
    }
    final scale = 842 / math.max(page.width, page.height);
    final image = pw.MemoryImage(page.bytes);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          page.width * scale,
          page.height * scale,
          marginAll: 0,
        ),
        build: (_) => pw.Image(image, fit: pw.BoxFit.contain),
      ),
    );
  }
  final bytes = await pdf.save();
  if (bytes.length > ScanImageLimits.maxPdfBytes) {
    throw const ScanFailure(
      'This PDF exceeds 100 MiB. Remove a page and try again.',
    );
  }
  return bytes;
}
