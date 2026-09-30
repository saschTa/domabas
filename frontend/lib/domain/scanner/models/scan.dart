import 'dart:math' as math;
import 'dart:typed_data';

import '../../document/models/document.dart';

final class ScanPoint {
  const ScanPoint(this.x, this.y);
  final double x;
  final double y;
}

final class ScanCorners {
  ScanCorners(Iterable<ScanPoint> points) : points = List.unmodifiable(points);
  factory ScanCorners.fullImage() => ScanCorners(const [
    ScanPoint(0, 0),
    ScanPoint(1, 0),
    ScanPoint(1, 1),
    ScanPoint(0, 1),
  ]);
  final List<ScanPoint> points;
  bool validFor(int width, int height) {
    if (width <= 0 || height <= 0 || points.length != 4) return false;
    if (points.any(
      (p) =>
          !p.x.isFinite ||
          !p.y.isFinite ||
          p.x < 0 ||
          p.x > 1 ||
          p.y < 0 ||
          p.y > 1,
    )) {
      return false;
    }
    var area = 0.0;
    final diagonal = math.sqrt(width * width + height * height);
    for (var i = 0; i < 4; i++) {
      final a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4];
      if ((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) <= 0) {
        return false;
      }
      final dx = (a.x - b.x) * width, dy = (a.y - b.y) * height;
      if (math.sqrt(dx * dx + dy * dy) < diagonal * .01) return false;
      area += a.x * b.y - b.x * a.y;
    }
    return area / 2 >= .01;
  }
}

enum ScanCameraStatus {
  idle,
  starting,
  ready,
  capturing,
  processing,
  suspended,
  denied,
  unavailable,
  closed,
}

final class ScanCameraState {
  const ScanCameraState({
    this.status = ScanCameraStatus.idle,
    this.width = 0,
    this.height = 0,
    this.rotation = 0,
    this.generation = 0,
    this.corners,
    this.message,
  });
  final ScanCameraStatus status;
  final int width;
  final int height;
  final int rotation;
  final int generation;
  final ScanCorners? corners;
  final String? message;
}

final class ScanCapture {
  ScanCapture({
    required this.id,
    required this.width,
    required this.height,
    required this.corners,
    required Uint8List preview,
  }) : preview = Uint8List.fromList(preview).asUnmodifiableView();
  final String id;
  final int width;
  final int height;
  final ScanCorners corners;
  final Uint8List preview;
}

final class ScanPage {
  ScanPage({
    required this.id,
    required this.width,
    required this.height,
    required Uint8List thumbnail,
  }) : thumbnail = Uint8List.fromList(thumbnail).asUnmodifiableView();
  final String id;
  final int width;
  final int height;
  final Uint8List thumbnail;
}

enum ScanDraftStatus { editable, uncertain, duplicate, accepted, blocked }

final class ScanDraft {
  ScanDraft({
    required this.id,
    required this.revision,
    required this.properties,
    Iterable<ScanPage> pages = const [],
    this.status = ScanDraftStatus.editable,
    this.message,
    this.acceptedDocumentId,
    this.cleanupPending = false,
  }) : pages = List.unmodifiable(pages);
  final String id;
  final int revision;
  final DocumentProperties properties;
  final List<ScanPage> pages;
  final ScanDraftStatus status;
  final String? message;
  final String? acceptedDocumentId;
  final bool cleanupPending;
  bool get editable => status == ScanDraftStatus.editable;
}

final class ScanFailure implements Exception {
  const ScanFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

final class ScanSubmission {
  const ScanSubmission(this.draft, {this.document});
  final ScanDraft draft;
  final Document? document;
  bool get accepted => draft.status == ScanDraftStatus.accepted;
}
