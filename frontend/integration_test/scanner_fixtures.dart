import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/scanner/interfaces/scan_draft_repository.dart';
import 'package:domabas/domain/scanner/interfaces/scanner_camera.dart';
import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:image/image.dart' as img;

DocumentProperties scanProperties([Map<String, Object> changes = const {}]) {
  final values = <String, Object>{
    'title': 'Scanner fixture',
    'description': '',
    'tags': <String>[],
    'kind': 'document',
    'sender': '',
    'recipients': <String>[],
    'cc': <String>[],
    'bcc': <String>[],
    'documentDate': '',
    'subject': '',
    'messageId': '',
    ...changes,
  };
  return DocumentProperties(
    title: values['title']! as String,
    description: values['description']! as String,
    tags: values['tags']! as List<String>,
    kind: values['kind']! as String,
    sender: values['sender']! as String,
    recipients: values['recipients']! as List<String>,
    cc: values['cc']! as List<String>,
    bcc: values['bcc']! as List<String>,
    documentDate: values['documentDate']! as String,
    subject: values['subject']! as String,
    messageId: values['messageId']! as String,
  );
}

Uint8List scanJpeg(
  int width,
  int height, {
  int red = 230,
  int green = 30,
  int blue = 30,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(red, green, blue));
  img.fillRect(
    image,
    x1: width ~/ 8,
    y1: height ~/ 8,
    x2: width ~/ 3,
    y2: height ~/ 3,
    color: img.ColorRgb8(255, 255, 255),
  );
  return img.encodeJpg(image, quality: 90);
}

class FixtureScannerCamera implements ScannerCamera {
  final controller = StreamController<ScanCameraState>.broadcast(sync: true);
  @override
  ScanCameraState state = const ScanCameraState();
  @override
  Stream<ScanCameraState> get states => controller.stream;
  Completer<void>? startGate;
  Completer<ScanCapture>? captureGate;
  int starts = 0, suspends = 0, captures = 0, releases = 0;
  bool denied = false, cancelled = false;
  void publish(ScanCameraState next) {
    state = next;
    controller.add(next);
  }

  @override
  Future<void> start() async {
    starts++;
    await startGate?.future;
    publish(
      ScanCameraState(
        status: denied ? ScanCameraStatus.denied : ScanCameraStatus.ready,
        width: 200,
        height: 300,
        message: denied
            ? 'Allow camera access in device settings, then try again.'
            : null,
      ),
    );
  }

  @override
  Future<void> suspend() async {
    suspends++;
    publish(const ScanCameraState(status: ScanCameraStatus.suspended));
  }

  @override
  Future<ScanCapture> capture() async {
    captures++;
    if (captureGate != null) return captureGate!.future;
    return ScanCapture(
      id: 'capture-$captures',
      width: 200,
      height: 300,
      corners: ScanCorners.fullImage(),
      preview: scanJpeg(200, 300),
    );
  }

  @override
  Future<void> releaseCapture(String id) async {
    releases++;
  }

  @override
  void cancelNewOperations() {
    cancelled = true;
  }

  @override
  Future<void> close() async {
    await controller.close();
  }
}

class FixtureScanRepository implements ScanDraftRepository {
  FixtureScanRepository({ScanDraft? initial})
    : draft =
          initial ??
          ScanDraft(id: 'fixture', revision: 0, properties: scanProperties());
  ScanDraft draft;
  int restores = 0, saves = 0, submissions = 0, cancellations = 0, moves = 0;
  Completer<void>? saveGate;
  Completer<void>? moveGate;
  Completer<ScanSubmission>? uploadGate;
  bool failMove = false;
  bool cancelled = false;
  @override
  Future<ScanDraft> restore() async {
    restores++;
    return draft;
  }

  @override
  Future<ScanDraft> saveProperties(DocumentProperties rawDraft) async {
    saves++;
    await saveGate?.future;
    draft = ScanDraft(
      id: draft.id,
      revision: draft.revision + 1,
      properties: rawDraft,
      pages: draft.pages,
    );
    return draft;
  }

  @override
  Future<ScanDraft> keepPage(ScanCapture capture, ScanCorners corners) async {
    draft = ScanDraft(
      id: draft.id,
      revision: draft.revision + 1,
      properties: draft.properties,
      pages: [
        ...draft.pages,
        ScanPage(
          id: capture.id,
          width: capture.width,
          height: capture.height,
          thumbnail: capture.preview,
        ),
      ],
    );
    return draft;
  }

  @override
  Future<ScanDraft> removePage(String id) async {
    draft = ScanDraft(
      id: draft.id,
      revision: draft.revision + 1,
      properties: draft.properties,
      pages: draft.pages.where((p) => p.id != id),
    );
    return draft;
  }

  @override
  Future<ScanDraft> movePage(String id, int finalIndex) async {
    moves++;
    await moveGate?.future;
    if (failMove) throw const ScanFailure('Page order could not be saved.');
    final pages = [...draft.pages];
    final originalIndex = pages.indexWhere((page) => page.id == id);
    if (!draft.editable ||
        originalIndex < 0 ||
        finalIndex < 0 ||
        finalIndex >= pages.length) {
      throw const ScanFailure('This page cannot be moved.');
    }
    if (originalIndex == finalIndex) return draft;
    pages.insert(finalIndex, pages.removeAt(originalIndex));
    draft = ScanDraft(
      id: draft.id,
      revision: draft.revision + 1,
      properties: draft.properties,
      pages: pages,
    );
    return draft;
  }

  @override
  Future<ScanSubmission> submit() async {
    submissions++;
    return uploadGate!.future;
  }

  @override
  Future<ScanSubmission> retryUpload() => submit();
  @override
  Future<ScanDraft> retryCleanup() async => draft;
  @override
  Future<void> discard() async {}
  @override
  void cancelSubmission() {
    cancellations++;
  }

  @override
  void cancelNewOperations() {
    cancelled = true;
  }

  @override
  Future<void> close() async {}
}
