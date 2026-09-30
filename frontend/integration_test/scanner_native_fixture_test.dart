import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    as platform;
import 'package:document_scan/document_scan.dart' as scan;
import 'package:domabas/app/scanner_scope.dart';
import 'package:domabas/data/scanner/datasources/native_scanner_camera.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native file detection and correction preserve EXIF orientation',
    (tester) async {
      await tester.runAsync(() async {
        expect(
          Platform.isIOS || Platform.isAndroid,
          isTrue,
          reason: 'Run this fixture on an iOS simulator/device or Android emulator/device.',
        );
        final root = await Directory.systemTemp.createTemp(
          'domabas-native-detector-',
        );
        try {
          for (final rotation in [0, 90]) {
            final source = _document();
            if (rotation == 90) {
              source.exif.imageIfd.orientation = 6;
            }
            final file = File('${root.path}/document-$rotation.jpg');
            await file.writeAsBytes(img.encodeJpg(source, quality: 95));
            await _export(
              'document-exif-$rotation.jpg',
              await file.readAsBytes(),
            );
            final input = scan.ScanInput.file(file.path);
            final corners = await scan.DocumentDetector().detect(input);
            expect(
              corners,
              isNotNull,
              reason: 'Native detector must find the EXIF $rotation document',
            );
            _expectCorners(corners!, rotation);
            final corrected = await const scan.DocumentProcessor().crop(
              input,
              corners,
            );
            expect(corrected, isNotNull);
            _expectMarkers(img.decodeImage(corrected!.bytes)!, rotation);
            await _export(
              'document-exif-$rotation-corrected.png',
              corrected.bytes,
            );
          }
        } finally {
          await root.delete(recursive: true);
        }
      });
    },
  );

  testWidgets(
    'native camera frame detection aligns with correction at all rotations',
    (tester) async {
      await tester.runAsync(() async {
        expect(
          Platform.isIOS || Platform.isAndroid,
          isTrue,
          reason: 'Run this fixture on an iOS simulator/device or Android emulator/device.',
        );
        final source = _document();
        final formats = Platform.isIOS
            ? [ImageFormatGroup.bgra8888]
            : [ImageFormatGroup.bgra8888, ImageFormatGroup.yuv420];
        for (final format in formats) {
          final frame = CameraImage.fromPlatformInterface(
            _cameraFrame(source, format),
          );
          for (final rotation in [0, 90, 180, 270]) {
            final input = NativeScannerCamera.frameInput(frame, rotation);
            final corners = await scan.DocumentDetector().detect(input);
            expect(
              corners,
              isNotNull,
              reason: 'Native $format detector must find the $rotation frame',
            );
            _expectCorners(corners!, rotation);
            final upright = img.copyRotate(source, angle: rotation);
            final corrected = await const scan.DocumentProcessor().crop(
              scan.ScanInput.bytes(
                img.encodePng(upright),
                width: upright.width,
                height: upright.height,
              ),
              corners,
            );
            expect(corrected, isNotNull);
            _expectMarkers(img.decodeImage(corrected!.bytes)!, rotation);
            await _export(
              'frame-${format.name()}-$rotation-corrected.png',
              corrected.bytes,
            );
          }
        }
      });
    },
  );

  testWidgets(
    'native scanner storage prepares, persists and discards an isolated draft',
    (tester) async {
      await tester.runAsync(() async {
        expect(
          Platform.isIOS || Platform.isAndroid,
          isTrue,
          reason: 'Run this fixture on an iOS simulator/device or Android emulator/device.',
        );
        final support = await getApplicationSupportDirectory();
        final scannerRoot = Directory('${support.path}/scanner-v1');
        final before = await scannerRoot.exists()
            ? (await scannerRoot.list(followLinks: false).toList())
                  .map((entry) => entry.path)
                  .toSet()
            : <String>{};
        final owner = 'native-fixture-${DateTime.now().microsecondsSinceEpoch}';
        final identity = Identity(
          userId: '$owner-user',
          email: '$owner@example.test',
          accountId: '$owner-library',
          accountName: 'Native scanner fixture',
          role: AccountRole.viewer,
          mustChangePassword: false,
          claims: const [IdentityPermission.uploadDocuments],
          permissions: const [IdentityPermission.uploadDocuments],
        );
        const endpoint = 'https://scanner-fixture.example.test/api';
        final client = api.ApiClient(basePath: endpoint);
        final coordinator = createScannerCoordinator();
        final factory = coordinator.forSession(endpoint, identity, client)!;
        ScannerScope? active;
        var persisted = false;
        try {
          final denied = coordinator.forSession(
            endpoint,
            Identity(
              userId: '$owner-denied',
              email: '$owner-denied@example.test',
              accountId: '$owner-library',
              accountName: 'Native scanner fixture',
              role: AccountRole.viewer,
              mustChangePassword: false,
              permissions: const [IdentityPermission.readDocuments],
            ),
            client,
          )!;
          try {
            await expectLater(denied.open(), throwsA(isA<ScanFailure>()));
          } finally {
            await denied.close();
          }
          active = await factory.open();
          expect(active.camera.state.status, ScanCameraStatus.idle);
          final draft = await active.repository.restore();
          expect(draft.status, ScanDraftStatus.editable);
          expect(draft.pages, isEmpty);
          expect(draft.properties.title, startsWith('Scan '));
          expect(draft.properties.kind, 'document');
          expect(
            draft.properties.documentDate,
            matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
          );
          final raw = DocumentProperties(
            title: '',
            description: ' Unfinished native fixture\n',
            tags: const [' keep spaces '],
            kind: 'document',
            sender: '',
            recipients: const ['unfinished address'],
            cc: const [],
            bcc: const [],
            documentDate: 'unfinished date',
            subject: '',
            messageId: '',
          );
          final saved = await active.repository.saveProperties(raw);
          expect(saved.status, ScanDraftStatus.editable);
          expect(saved.revision, draft.revision + 1);
          expect(saved.properties.values, raw.values);
          persisted = true;
          await active.close();
          active = null;
          active = await factory.open();
          final restored = await active.repository.restore();
          expect(restored.id, draft.id);
          expect(restored.revision, saved.revision);
          expect(restored.status, ScanDraftStatus.editable);
          expect(restored.properties.values, raw.values);
          expect(active.camera.state.status, ScanCameraStatus.idle);
        } finally {
          try {
            if (active != null) {
              await active.repository.discard();
            } else if (persisted) {
              final cleanup = await factory.open();
              try {
                await cleanup.repository.discard();
              } finally {
                await cleanup.close();
              }
            }
          } finally {
            try {
              await factory.close();
            } finally {
              client.client.close();
            }
          }
        }
        expect(
          (await scannerRoot.list(followLinks: false).toList())
              .map((entry) => entry.path)
              .toSet(),
          before,
        );
      });
    },
  );
}

Future<void> _export(String name, Uint8List bytes) async {
  if (!const bool.fromEnvironment('SCANNER_FIXTURE_EXPORT')) {
    return;
  }
  final documents = await getApplicationDocumentsDirectory();
  final directory = Directory('${documents.path}/scanner-fixture-evidence');
  await directory.create(recursive: true);
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  debugPrint('Scanner native fixture artifact: ${file.path}');
}

img.Image _document() {
  final image = img.Image(width: 800, height: 1000);
  img.fill(image, color: img.ColorRgb8(25, 25, 25));
  img.fillRect(
    image,
    x1: 80,
    y1: 90,
    x2: 620,
    y2: 910,
    color: img.ColorRgb8(250, 250, 250),
  );
  for (final marker in [
    (x: 161, y: 213, color: img.ColorRgb8(230, 20, 20)),
    (x: 539, y: 213, color: img.ColorRgb8(20, 230, 20)),
    (x: 161, y: 787, color: img.ColorRgb8(20, 20, 230)),
    (x: 539, y: 787, color: img.ColorRgb8(230, 230, 20)),
  ]) {
    img.fillRect(
      image,
      x1: marker.x - 35,
      y1: marker.y - 45,
      x2: marker.x + 35,
      y2: marker.y + 45,
      color: marker.color,
    );
  }
  for (var row = 0; row < 9; row++) {
    img.fillRect(
      image,
      x1: 200,
      y1: 330 + row * 35,
      x2: 500 - (row % 3) * 35,
      y2: 336 + row * 35,
      color: img.ColorRgb8(45, 45, 45),
    );
  }
  return image;
}

platform.CameraImageData _cameraFrame(
  img.Image image,
  ImageFormatGroup format,
) {
  final planes = <platform.CameraImagePlane>[];
  if (format == ImageFormatGroup.bgra8888) {
    final packed = image.getBytes(order: img.ChannelOrder.bgra);
    final stride = image.width * 4 + 16;
    final padded = Uint8List(stride * image.height);
    for (var row = 0; row < image.height; row++) {
      padded.setRange(
        row * stride,
        row * stride + image.width * 4,
        packed,
        row * image.width * 4,
      );
    }
    planes.add(
      platform.CameraImagePlane(
        bytes: padded,
        bytesPerRow: stride,
        bytesPerPixel: 4,
      ),
    );
  } else {
    final yStride = image.width + 16;
    final uvStride = image.width + 8;
    final y = Uint8List(yStride * image.height);
    for (var row = 0; row < image.height; row++) {
      for (var column = 0; column < image.width; column++) {
        final pixel = image.getPixel(column, row);
        y[row * yStride + column] =
            (16 + .257 * pixel.r + .504 * pixel.g + .098 * pixel.b).round();
      }
    }
    planes.add(
      platform.CameraImagePlane(
        bytes: y,
        bytesPerRow: yStride,
        bytesPerPixel: 1,
      ),
    );
    for (var channel = 0; channel < 2; channel++) {
      final chroma = Uint8List(uvStride * (image.height ~/ 2));
      chroma.fillRange(0, chroma.length, 128);
      planes.add(
        platform.CameraImagePlane(
          bytes: chroma,
          bytesPerRow: uvStride,
          bytesPerPixel: 2,
        ),
      );
    }
  }
  return platform.CameraImageData(
    format: platform.CameraImageFormat(format, raw: format.index),
    width: image.width,
    height: image.height,
    planes: planes,
  );
}

void _expectCorners(scan.DocumentCorners corners, int rotation) {
  final expected = switch (rotation) {
    0 => [
      (x: .10, y: .09),
      (x: .775, y: .09),
      (x: .775, y: .91),
      (x: .10, y: .91),
    ],
    90 => [
      (x: .09, y: .10),
      (x: .91, y: .10),
      (x: .91, y: .775),
      (x: .09, y: .775),
    ],
    180 => [
      (x: .225, y: .09),
      (x: .90, y: .09),
      (x: .90, y: .91),
      (x: .225, y: .91),
    ],
    270 => [
      (x: .09, y: .225),
      (x: .91, y: .225),
      (x: .91, y: .90),
      (x: .09, y: .90),
    ],
    _ => throw ArgumentError.value(rotation),
  };
  final actual = corners.toList();
  for (var index = 0; index < 4; index++) {
    expect(
      actual[index].x,
      closeTo(expected[index].x, .025),
      reason: 'rotation $rotation corner $index x',
    );
    expect(
      actual[index].y,
      closeTo(expected[index].y, .025),
      reason: 'rotation $rotation corner $index y',
    );
  }
}

void _expectMarkers(img.Image image, int rotation) {
  final colors = switch (rotation) {
    0 => ['red', 'green', 'blue', 'yellow'],
    90 => ['blue', 'red', 'yellow', 'green'],
    180 => ['yellow', 'blue', 'green', 'red'],
    270 => ['green', 'yellow', 'red', 'blue'],
    _ => throw ArgumentError.value(rotation),
  };
  final points = [
    (x: .15, y: .15),
    (x: .85, y: .15),
    (x: .15, y: .85),
    (x: .85, y: .85),
  ];
  for (var index = 0; index < 4; index++) {
    final color = colors[index];
    final expected = switch (color) {
      'red' => (230, 20, 20),
      'green' => (20, 230, 20),
      'blue' => (20, 20, 230),
      'yellow' => (230, 230, 20),
      _ => throw ArgumentError.value(color),
    };
    final point = points[index];
    final pixel = image.getPixel(
      (image.width * point.x).floor(),
      (image.height * point.y).floor(),
    );
    expect(
      pixel.r,
      closeTo(expected.$1, 35),
      reason: '$rotation $color red channel',
    );
    expect(
      pixel.g,
      closeTo(expected.$2, 35),
      reason: '$rotation $color green channel',
    );
    expect(
      pixel.b,
      closeTo(expected.$3, 35),
      reason: '$rotation $color blue channel',
    );
  }
  expect(
    image.width / image.height,
    closeTo(rotation == 0 || rotation == 180 ? 540 / 820 : 820 / 540, .08),
  );
}
