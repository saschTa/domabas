import 'dart:async';
import 'dart:typed_data';

import 'package:document_scan/document_scan.dart' as scan;
import 'package:domabas/data/scanner/datasources/adaptive_scan_detector.dart';
import 'package:domabas/data/scanner/datasources/scan_detection_contrast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'faint page boundaries gain contrast without changing source pixels',
    () {
      final input = _frame();
      final before = Uint8List.fromList(input.bytes!);
      final enhanced = prepareScanDetectionContrast(input)!;
      final row = enhanced.height ~/ 2;
      final outside = enhanced.bytes![(row * enhanced.width + 18) * 4];
      final inside = enhanced.bytes![(row * enhanced.width + 22) * 4];
      expect(inside - outside, greaterThan(30));
      expect(input.bytes, before);
      expect(enhanced.rotation, input.rotation);
      expect(enhanced.bytesPerRow, enhanced.width * 4);
    },
  );

  test('luminance respects BGRA and YUV row strides at every rotation', () {
    for (final rotation in [0, 90, 180, 270]) {
      final packed = _frame(rotation: rotation);
      final stride = packed.width * 4 + 16;
      final padded = Uint8List(stride * packed.height)
        ..fillRange(0, stride * packed.height, 255);
      final yStride = packed.width + 8;
      final luminance = Uint8List(yStride * packed.height)
        ..fillRange(0, yStride * packed.height, 255);
      for (var y = 0; y < packed.height; y++) {
        padded.setRange(
          y * stride,
          y * stride + packed.width * 4,
          packed.bytes!,
          y * packed.width * 4,
        );
        for (var x = 0; x < packed.width; x++) {
          luminance[y * yStride + x] =
              packed.bytes![(y * packed.width + x) * 4];
        }
      }
      final bgra = scan.ScanInput.bgraFrame(
        width: packed.width,
        height: packed.height,
        bytes: padded,
        bytesPerRow: stride,
        rotation: rotation,
      );
      final yuv = scan.ScanInput.yuvFrame(
        width: packed.width,
        height: packed.height,
        yBytes: luminance,
        uBytes: Uint8List(0),
        vBytes: Uint8List(0),
        yRowStride: yStride,
        rotation: rotation,
      );
      final expected = prepareScanDetectionContrast(packed)!;
      for (final frame in [bgra, yuv]) {
        final actual = prepareScanDetectionContrast(frame)!;
        expect(actual.bytes, expected.bytes);
        expect(actual.rotation, rotation);
      }
    }
  });

  test('analysis is bounded and retains the full image proportions', () {
    final input = _frame(width: 1600, height: 1000);
    final enhanced = prepareScanDetectionContrast(input)!;
    expect((enhanced.width, enhanced.height), (720, 450));
    expect(enhanced.bytes!.length, 720 * 450 * 4);
  });

  test(
    'flat scenes and minor sensor noise do not get amplified into pages',
    () {
      for (final noise in [false, true]) {
        final bytes = Uint8List(64 * 64 * 4);
        for (var i = 0; i < bytes.length; i += 4) {
          final value = 220 + (noise ? (i ~/ 4 * 31) % 5 : 0);
          bytes[i] = bytes[i + 1] = bytes[i + 2] = value;
          bytes[i + 3] = 255;
        }
        expect(
          prepareScanDetectionContrast(
            scan.ScanInput.bgraFrame(width: 64, height: 64, bytes: bytes),
          ),
          isNull,
        );
      }
    },
  );

  test('encoded EXIF previews are upright before analysis', () {
    final image = img.Image.fromBytes(
      width: 160,
      height: 120,
      bytes: _frame().bytes!.buffer,
      order: img.ChannelOrder.bgra,
    );
    image.exif.imageIfd.orientation = 6;
    final enhanced = prepareScanDetectionContrast(
      scan.ScanInput.bytes(img.encodeJpg(image), width: 160, height: 120),
    )!;
    expect((enhanced.width, enhanced.height, enhanced.rotation), (120, 160, 0));
  });

  test('successful ordinary detection does not reprocess the frame', () async {
    final native = _Detector([_corners()]);
    final result = await AdaptiveScanDetector(detector: native)
        .detect(_frame());
    expect(result, _corners());
    expect(native.inputs, hasLength(1));
    expect(native.sensitivities, [scan.DetectionSensitivity.balanced]);
  });

  test(
    'a missed page retries enhanced pixels once at higher sensitivity',
    () async {
      final input = _frame();
      final native = _Detector([null, _corners()]);
      final result = await AdaptiveScanDetector(detector: native).detect(input);
      expect(result, _corners());
      expect(native.inputs, hasLength(2));
      expect(native.sensitivities, [
        scan.DetectionSensitivity.balanced,
        scan.DetectionSensitivity.lenient,
      ]);
      expect(
        (native.inputs.last as scan.CameraFrameScanInput).bytes,
        isNot(input.bytes),
      );
    },
  );

  test(
    'cancellation while native detection is pending prevents fallback',
    () async {
      final native = _Detector([null])..gate = Completer<void>();
      var current = true;
      final detecting = AdaptiveScanDetector(detector: native)
          .detect(_frame(), isCurrent: () => current);
      current = false;
      native.gate!.complete();
      expect(await detecting, isNull);
      expect(native.inputs, hasLength(1));
    },
  );

  test('still fallback uses its bounded upright preview without rereading the file', () async {
    final frame = _frame();
    final preview = img.encodeJpg(
      img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.bytes!.buffer,
        order: img.ChannelOrder.bgra,
      ),
    );
    final native = _Detector([null, _corners()]);
    final result = await AdaptiveScanDetector(detector: native).detect(
      scan.ScanInput.file('/not-a-real-capture.jpg'),
      uprightPreview: preview,
    );
    expect(result, _corners());
    final enhanced = native.inputs.last as scan.CameraFrameScanInput;
    expect((enhanced.width, enhanced.height, enhanced.rotation), (160, 120, 0));
  });

  test(
    'cancellation during contrast preparation prevents the second native pass',
    () async {
      final native = _Detector([null]);
      var checks = 0;
      final result = await AdaptiveScanDetector(detector: native)
          .detect(_frame(), isCurrent: () => ++checks == 1);
      expect(result, isNull);
      expect(native.inputs, hasLength(1));
    },
  );

  test(
    'noise strips from the ordinary detector are not accepted as pages',
    () async {
      final native = _Detector([
        _corners(left: .8, top: 0, right: .94, bottom: 1),
        null,
      ]);
      expect(
        await AdaptiveScanDetector(detector: native).detect(_frame()),
        isNull,
      );
      expect(native.inputs, hasLength(2));
    },
  );

  test(
    'fallback rejects tiny, whole-frame and crossed quadrilaterals',
    () async {
      for (final candidate in [
        _corners(left: .4, top: .4, right: .5, bottom: .5),
        _corners(left: 0, top: 0, right: 1, bottom: 1),
        const scan.DocumentCorners(
          topLeft: (x: .1, y: .1),
          topRight: (x: .8, y: .8),
          bottomRight: (x: .8, y: .1),
          bottomLeft: (x: .1, y: .8),
        ),
      ]) {
        final native = _Detector([null, candidate]);
        expect(
          await AdaptiveScanDetector(detector: native).detect(_frame()),
          isNull,
        );
      }
    },
  );
}

scan.CameraFrameScanInput _frame({
  int width = 160,
  int height = 120,
  int rotation = 0,
}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final page =
          x >= width ~/ 8 &&
          x < width * 7 ~/ 8 &&
          y >= height ~/ 8 &&
          y < height * 7 ~/ 8;
      final value = page ? 224 : 210;
      final offset = (y * width + x) * 4;
      bytes[offset] = bytes[offset + 1] = bytes[offset + 2] = value;
      bytes[offset + 3] = 255;
    }
  }
  return scan.ScanInput.bgraFrame(
    width: width,
    height: height,
    bytes: bytes,
    rotation: rotation,
  ) as scan.CameraFrameScanInput;
}

scan.DocumentCorners _corners({
  double left = .1,
  double top = .1,
  double right = .8,
  double bottom = .9,
}) => scan.DocumentCorners(
  topLeft: (x: left, y: top),
  topRight: (x: right, y: top),
  bottomRight: (x: right, y: bottom),
  bottomLeft: (x: left, y: bottom),
);

class _Detector extends scan.DocumentDetector {
  _Detector(this.results);
  final List<scan.DocumentCorners?> results;
  final inputs = <scan.ScanInput>[];
  final sensitivities = <scan.DetectionSensitivity>[];
  Completer<void>? gate;
  @override
  Future<scan.DocumentCorners?> detect(
    scan.ScanInput input, {
    scan.DetectionSensitivity sensitivity = scan.DetectionSensitivity.balanced,
  }) async {
    inputs.add(input);
    sensitivities.add(sensitivity);
    await gate?.future;
    return results.removeAt(0);
  }
}
