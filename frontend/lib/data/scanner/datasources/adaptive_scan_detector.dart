import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_scan/document_scan.dart' as scan;

import '../../../domain/scanner/models/scan.dart';
import 'scan_detection_contrast.dart';

final class AdaptiveScanDetector {
  AdaptiveScanDetector({scan.DocumentDetector? detector})
    : _detector = detector ?? scan.DocumentDetector();

  final scan.DocumentDetector _detector;

  Future<scan.DocumentCorners?> detect(
    scan.ScanInput input, {
    Uint8List? uprightPreview,
    bool Function()? isCurrent,
  }) async {
    final original = await _detector.detect(input);
    if (isCurrent?.call() == false) return null;
    if (original != null && _validDocument(original)) return original;
    final enhanced = await Isolate.run(
      () => prepareScanDetectionContrast(input, uprightPreview: uprightPreview),
    );
    if (enhanced == null || isCurrent?.call() == false) return null;
    final candidate = await _detector.detect(
      enhanced,
      sensitivity: scan.DetectionSensitivity.lenient,
    );
    if (candidate == null || isCurrent?.call() == false) return null;
    return _validDocument(candidate) ? candidate : null;
  }

  bool _validDocument(scan.DocumentCorners candidate) {
    final points = candidate.toList();
    final corners = ScanCorners(points.map((p) => ScanPoint(p.x, p.y)));
    if (!corners.validFor(1, 1)) return false;
    final xs = points.map((p) => p.x), ys = points.map((p) => p.y);
    if ((xs.reduce(math.min) < .005 && xs.reduce(math.max) > .995) ||
        (ys.reduce(math.min) < .005 && ys.reduce(math.max) > .995)) {
      return false;
    }
    var area = 0.0;
    var shortest = double.infinity, longest = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = points[i], b = points[(i + 1) % 4];
      area += a.x * b.y - b.x * a.y;
      final lengthSquared = math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2);
      shortest = math.min(shortest, lengthSquared.toDouble());
      longest = math.max(longest, lengthSquared.toDouble());
    }
    return area / 2 >= .06 && area / 2 <= .95 && shortest / longest >= .01;
  }
}
