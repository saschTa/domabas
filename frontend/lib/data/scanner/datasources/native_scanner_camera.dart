import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:document_scan/document_scan.dart' as scan;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../../domain/scanner/models/scan.dart';
import '../models/scan_assets.dart';
import '../models/scan_image_limits.dart';
import '../repos/scan_capture_data_port.dart';
import 'adaptive_scan_detector.dart';
import 'scan_storage_coordinator.dart';

final class NativeScannerCamera implements ScanCaptureDataPort {
  @override
  bool get usesSystemCapture => false;
  NativeScannerCamera(this.lease, {scan.DocumentDetector? detector})
    : _detector = AdaptiveScanDetector(detector: detector);
  final ScanStorageLease lease;
  final AdaptiveScanDetector _detector;
  final _states = StreamController<ScanCameraState>.broadcast();
  final _stabilizer = scan.CornerStabilizer();
  CameraController? _controller;
  CameraController? get currentController => _controller;
  ScanCameraState _state = const ScanCameraState();
  @override
  ScanCameraState get state => _state;
  @override
  Stream<ScanCameraState> get states => _states.stream;
  Future<void> _tail = Future.value();
  Future<void>? _detection;
  void Function()? _releaseCamera;
  bool _cancelled = false, _wanted = false;
  bool _capturing = false;
  int _generation = 0;
  DeviceOrientation? _orientation;
  DateTime _lastDetection = DateTime.fromMillisecondsSinceEpoch(0);
  String? _captureId, _capturePath;
  ScanReservation? _captureReservation;
  ScanReservation? _readyReservation;
  int _width = 0, _height = 0;

  Future<T> _run<T>(Future<T> Function() work, {bool cleanup = false}) {
    final result = _tail.then((_) {
      if (_cancelled && !cleanup) {
        throw const ScanFailure('This camera session has ended.');
      }
      return work();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _emit(ScanCameraState state) {
    _state = state;
    if (!_cancelled && !_states.isClosed) _states.add(state);
  }

  @override
  Future<void> start() {
    _wanted = true;
    return _run(() async {
      if (!_wanted || _controller != null) return;
      final generation = ++_generation;
      _emit(
        ScanCameraState(
          status: ScanCameraStatus.starting,
          generation: generation,
        ),
      );
      try {
        _releaseCamera = await lease.coordinator.acquireCamera();
        if (_cancelled || !_wanted || generation != _generation) {
          _releaseCamera?.call();
          _releaseCamera = null;
          return;
        }
        final cameras = await availableCameras();
        if (_cancelled || !_wanted || generation != _generation) {
          await _teardown();
          return;
        }
        final rearCameras = cameras.where(
          (camera) => camera.lensDirection == CameraLensDirection.back,
        );
        final rear =
            rearCameras
                .where((camera) => camera.lensType == CameraLensType.wide)
                .firstOrNull ??
            rearCameras.firstOrNull;
        if (rear == null) {
          throw const ScanFailure(
            'No rear camera is available on this device.',
          );
        }
        final controller = CameraController(
          rear,
          ResolutionPreset.max,
          enableAudio: false,
          imageFormatGroup: Platform.isIOS
              ? ImageFormatGroup.bgra8888
              : ImageFormatGroup.yuv420,
        );
        _controller = controller;
        await controller.initialize();
        if (_cancelled || !_wanted || generation != _generation) {
          await _teardown();
          return;
        }
        await _configureCapture(controller);
        await _releaseInput();
        _readyReservation = await lease.reserve(
          ScanImageLimits.captureReservationBytes,
          scratch: true,
        );
        lease.scratchBytes += ScanImageLimits.captureReservationBytes;
        if (_cancelled || !_wanted || generation != _generation) {
          await _teardown();
          return;
        }
        _orientation = controller.value.deviceOrientation;
        controller.addListener(_orientationChanged);
        await controller.startImageStream(_frame);
        if (_cancelled || !_wanted) {
          await _teardown();
          return;
        }
        final size = controller.value.previewSize!;
        final portrait = _portrait(controller.value.deviceOrientation);
        _emit(
          ScanCameraState(
            status: ScanCameraStatus.ready,
            width:
                (portrait
                        ? math.min(size.width, size.height)
                        : math.max(size.width, size.height))
                    .round(),
            height:
                (portrait
                        ? math.max(size.width, size.height)
                        : math.min(size.width, size.height))
                    .round(),
            generation: _generation,
          ),
        );
      } catch (error) {
        await _teardown();
        final denied =
            error is CameraException && error.code.contains('Access');
        _emit(
          ScanCameraState(
            status: denied
                ? ScanCameraStatus.denied
                : ScanCameraStatus.unavailable,
            generation: _generation,
            message: denied
                ? 'Allow camera access in device settings, then try again.'
                : error is ScanFailure
                ? error.message
                : 'The camera could not start. Try again.',
          ),
        );
      }
    });
  }

  Future<void> _configureCapture(CameraController controller) async {
    for (final setting in <Future<void> Function()>[
      () => controller.setJpegImageQuality(100),
      () => controller.setFlashMode(FlashMode.off),
      () => controller.setFocusMode(FocusMode.auto),
      () => controller.setExposureMode(ExposureMode.auto),
      () async {
        final minimum = await controller.getMinExposureOffset();
        final maximum = await controller.getMaxExposureOffset();
        await controller.setExposureOffset((-1.0).clamp(minimum, maximum));
      },
    ]) {
      try {
        await setting();
      } on CameraException {
        continue;
      } on UnimplementedError {
        continue;
      }
    }
  }

  bool _portrait(DeviceOrientation value) =>
      value == DeviceOrientation.portraitUp ||
      value == DeviceOrientation.portraitDown;
  void _orientationChanged() {
    final orientation = _controller?.value.deviceOrientation;
    if (orientation == null || orientation == _orientation) return;
    _orientation = orientation;
    _generation++;
    _stabilizer.reset();
    final size = _controller!.value.previewSize;
    _emit(
      ScanCameraState(
        status: _state.status,
        width: size == null
            ? 0
            : (_portrait(orientation)
                      ? math.min(size.width, size.height)
                      : math.max(size.width, size.height))
                  .round(),
        height: size == null
            ? 0
            : (_portrait(orientation)
                      ? math.max(size.width, size.height)
                      : math.min(size.width, size.height))
                  .round(),
        generation: _generation,
      ),
    );
  }

  int _rotation(CameraController controller) {
    if (Platform.isIOS) return 0;
    final degrees = switch (controller.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    return (controller.description.sensorOrientation - degrees + 360) % 360;
  }

  void _frame(CameraImage image) {
    final controller = _controller;
    if (_cancelled ||
        !_wanted ||
        _capturing ||
        controller == null ||
        _detection != null ||
        _state.status != ScanCameraStatus.ready ||
        DateTime.now().difference(_lastDetection).inMilliseconds < 100) {
      return;
    }
    final generation = _generation;
    final rotation = _rotation(controller);
    _lastDetection = DateTime.now();
    final operation = () async {
      try {
        final input = frameInput(image, rotation);
        final width = rotation == 90 || rotation == 270
            ? image.height
            : image.width;
        final height = rotation == 90 || rotation == 270
            ? image.width
            : image.height;
        final preview = controller.value.previewSize;
        final portrait = _portrait(controller.value.deviceOrientation);
        final previewWidth = preview == null
            ? 0
            : (portrait
                      ? math.min(preview.width, preview.height)
                      : math.max(preview.width, preview.height))
                  .round();
        final previewHeight = preview == null
            ? 0
            : (portrait
                      ? math.max(preview.width, preview.height)
                      : math.min(preview.width, preview.height))
                  .round();
        if (previewWidth <= 0 ||
            previewHeight <= 0 ||
            (width * previewHeight / (height * previewWidth) - 1).abs() > .01) {
          throw const ScanFailure(
            'This camera uses a different framing area for detection. Capture and adjust the page corners manually.',
          );
        }
        final detected = await _detector.detect(
          input,
          isCurrent: () => generation == _generation && _wanted && !_cancelled,
        );
        if (generation != _generation || !_wanted || _cancelled) return;
        final corners = _stabilizer.add(detected);
        final mapped = corners == null ? null : _scanCornersMapper(corners);
        _emit(
          ScanCameraState(
            status: ScanCameraStatus.ready,
            width: previewWidth,
            height: previewHeight,
            rotation: rotation,
            generation: generation,
            corners: mapped?.validFor(width, height) == true ? mapped : null,
          ),
        );
      } catch (error) {
        _stabilizer.reset();
        if (generation == _generation &&
            !_cancelled &&
            _wanted &&
            !_capturing) {
          _emit(
            ScanCameraState(
              status: ScanCameraStatus.ready,
              width: _state.width,
              height: _state.height,
              generation: generation,
              message: error is ScanFailure ? error.message : 'Edge detection is unavailable. Capture and adjust the corners manually.',
            ),
          );
        }
      }
    }();
    _detection = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_detection, operation)) _detection = null;
      }),
    );
  }

  static scan.ScanInput frameInput(CameraImage image, int rotation) {
    if (image.width <= 0 ||
        image.height <= 0 ||
        image.width * image.height > 20000000) {
      throw const ScanFailure('Unsupported camera frame dimensions.');
    }
    bool extent(Plane plane, int width, int height, int pixelStride) =>
        plane.bytesPerRow >= (width - 1) * pixelStride + 1 &&
        plane.bytes.length >=
            (height - 1) * plane.bytesPerRow + (width - 1) * pixelStride + 1;
    if (image.format.group == ImageFormatGroup.bgra8888) {
      if (image.planes.length != 1 ||
          image.planes.first.bytesPerRow < image.width * 4 ||
          image.planes.first.bytes.length <
              image.height * image.planes.first.bytesPerRow) {
        throw const ScanFailure(
          'Unsupported BGRA camera layout. Capture and correct manually.',
        );
      }
      return scan.ScanInput.bgraFrame(
        width: image.width,
        height: image.height,
        bytes: image.planes.first.bytes,
        bytesPerRow: image.planes.first.bytesPerRow,
        rotation: rotation,
      );
    }
    if (image.format.group != ImageFormatGroup.yuv420 ||
        image.planes.length != 3) {
      throw const ScanFailure(
        'Unsupported YUV camera layout. Capture and correct manually.',
      );
    }
    final y = image.planes[0], u = image.planes[1], v = image.planes[2];
    final uvPixel = u.bytesPerPixel ?? 1;
    if ((y.bytesPerPixel ?? 1) != 1 ||
        uvPixel < 1 ||
        uvPixel > 2 ||
        u.bytesPerRow != v.bytesPerRow ||
        uvPixel != (v.bytesPerPixel ?? 1) ||
        !extent(y, image.width, image.height, 1) ||
        !extent(u, (image.width + 1) ~/ 2, (image.height + 1) ~/ 2, uvPixel) ||
        !extent(v, (image.width + 1) ~/ 2, (image.height + 1) ~/ 2, uvPixel)) {
      throw const ScanFailure(
        'Unsupported YUV plane strides. Capture and correct manually.',
      );
    }
    return scan.ScanInput.yuvFrame(
      width: image.width,
      height: image.height,
      yBytes: y.bytes,
      uBytes: u.bytes,
      vBytes: v.bytes,
      yRowStride: y.bytesPerRow,
      uvRowStride: u.bytesPerRow,
      uvPixelStride: uvPixel,
      rotation: rotation,
    );
  }

  @override
  Future<ScanCapture> capture() {
    final controller = _controller;
    if (_capturing) {
      return Future.error(
        const ScanFailure('A page is already being captured.'),
      );
    }
    if (_cancelled ||
        !_wanted ||
        controller == null ||
        !controller.value.isInitialized ||
        _state.status != ScanCameraStatus.ready) {
      return Future.error(
        const ScanFailure('Start the camera before capturing a page.'),
      );
    }
    _capturing = true;
    _wanted = false;
    final generation = ++_generation;
    _emitCapturePhase(ScanCameraStatus.capturing);
    return _run(() => _capture(controller, generation))
        .whenComplete(() => _capturing = false);
  }

  void _checkCaptureSession(CameraController controller, int generation) {
    if (_cancelled ||
        lease.cancelled ||
        generation != _generation ||
        !identical(_controller, controller) ||
        !controller.value.isInitialized) {
      throw const ScanFailure('The camera changed before capture. Try again.');
    }
  }

  void _emitCapturePhase(ScanCameraStatus status) {
    _emit(
      ScanCameraState(
        status: status,
        width: _state.width,
        height: _state.height,
        rotation: _state.rotation,
        generation: _generation,
        corners: _state.corners,
      ),
    );
  }

  Future<ScanCapture> _capture(
    CameraController controller,
    int generation,
  ) async {
    String? original;
    try {
      _checkCaptureSession(controller, generation);
      if (_readyReservation == null || _captureReservation != null) {
        throw const ScanFailure('Restart the camera before capturing a page.');
      }
      _captureReservation = _readyReservation;
      _readyReservation = null;
      final photo = await controller.takePicture();
      original = photo.path;
      _emitCapturePhase(ScanCameraStatus.processing);
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await _detection;
      final id = _id();
      final path = '${lease.directory.path}/scratch-$id.jpg';
      _capturePath = path;
      _captureId = id;
      final prepared = await lease.coordinator.imageWork(
        () => _prepareCaptureInBackground(photo.path, path),
      );
      _capturePath = path;
      _captureId = id;
      _width = prepared.width;
      _height = prepared.height;
      scan.DocumentCorners? detected;
      try {
        detected = await lease.coordinator.imageWork(
          () => _detector.detect(
            scan.ScanInput.file(path),
            uprightPreview: prepared.preview,
            isCurrent: () => !_cancelled && !lease.cancelled,
          ),
        );
      } catch (_) {
        detected = null;
      }
      final corners = detected == null
          ? ScanCorners.fullImage()
          : _scanCornersMapper(detected);
      _wanted = false;
      await _teardown();
      return ScanCapture(
        id: id,
        width: _width,
        height: _height,
        corners: corners.validFor(_width, _height)
            ? corners
            : ScanCorners.fullImage(),
        preview: prepared.preview,
      );
    } catch (_) {
      try {
        if (original != null) {
          final file = File(original);
          if (await file.exists()) await file.delete();
        }
      } finally {
        try {
          await _releaseInput();
        } finally {
          await _teardown();
        }
      }
      rethrow;
    }
  }

  @override
  Future<CorrectedScanPage> correct(ScanCapture capture, ScanCorners corners) =>
      _run(() async {
        if (_captureId != capture.id ||
            _capturePath == null ||
            capture.width != _width ||
            capture.height != _height) {
          throw const ScanFailure('Capture this page again.');
        }
        if (!corners.validFor(_width, _height)) {
          throw const ScanFailure(
            'Keep four corners around a convex document area.',
          );
        }
        final points = corners.points;
        double edge(int a, int b) => math.sqrt(
          math.pow((points[a].x - points[b].x) * _width, 2) +
              math.pow((points[a].y - points[b].y) * _height, 2),
        );
        final width = ((edge(0, 1) + edge(3, 2)) / 2).round();
        final height = ((edge(0, 3) + edge(1, 2)) / 2).round();
        if (!ScanImageLimits.validDimensions(width, height)) {
          throw const ScanFailure('This page exceeds the 50 megapixel limit.');
        }
        final reservation = await lease.reserve(
          ScanImageLimits.correctionReservationBytes,
          scratch: true,
        );
        lease.scratchBytes += ScanImageLimits.correctionReservationBytes;
        final input = _capturePath!;
        try {
          return await lease.coordinator.imageWork(
            () => _correctCaptureInBackground(input, corners),
          );
        } finally {
          lease.scratchBytes -= ScanImageLimits.correctionReservationBytes;
          reservation.release();
        }
      });

  @override
  Future<void> releaseCapture(String id) => _run(() async {
    if (_captureId == id) await _releaseInput();
  }, cleanup: true);
  Future<void> _releaseInput() async {
    final path = _capturePath;
    if (path != null && await File(path).exists()) await File(path).delete();
    _capturePath = null;
    _captureId = null;
    if (_captureReservation != null) {
      lease.scratchBytes -= ScanImageLimits.captureReservationBytes;
      _captureReservation!.release();
      _captureReservation = null;
    }
  }

  @override
  Future<void> suspend() {
    _wanted = false;
    _generation++;
    return _run(_teardown, cleanup: true);
  }

  Future<void> _teardown() async {
    final controller = _controller;
    try {
      if (controller != null) {
        controller.removeListener(_orientationChanged);
        try {
          if (controller.value.isStreamingImages) {
            await controller.stopImageStream();
          }
        } finally {
          await _detection;
          await controller.dispose();
        }
      }
    } finally {
      if (_readyReservation != null) {
        lease.scratchBytes -= ScanImageLimits.captureReservationBytes;
        _readyReservation!.release();
        _readyReservation = null;
      }
      if (identical(_controller, controller)) {
        _controller = null;
      }
      _stabilizer.reset();
      _releaseCamera?.call();
      _releaseCamera = null;
      _emit(
        ScanCameraState(
          status: ScanCameraStatus.suspended,
          generation: _generation,
        ),
      );
    }
  }

  @override
  void cancelNewOperations() {
    _cancelled = true;
    _wanted = false;
    _generation++;
  }

  Future<void>? _closing;
  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    cancelNewOperations();
    try {
      await _run(() async {
        try {
          await _teardown();
        } finally {
          await _releaseInput();
        }
      }, cleanup: true);
    } finally {
      await _states.close();
    }
  }

  static ScanCorners _scanCornersMapper(scan.DocumentCorners corners) =>
      ScanCorners(corners.toList().map((p) => ScanPoint(p.x, p.y)));
  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}';
}

final class _PreparedScanCapture {
  const _PreparedScanCapture(this.width, this.height, this.preview);
  final int width, height;
  final Uint8List preview;
}

Future<_PreparedScanCapture> _prepareCaptureInBackground(
  String original,
  String target,
) => Isolate.run(() => _prepareCapture(original, target));

Future<CorrectedScanPage> _correctCaptureInBackground(
  String input,
  ScanCorners corners,
) => Isolate.run(() async {
  final points = corners.points.map((p) => (x: p.x, y: p.y)).toList();
  final corrected = await const scan.DocumentProcessor().crop(
    scan.ScanInput.file(input),
    scan.DocumentCorners(
      topLeft: points[0],
      topRight: points[1],
      bottomRight: points[2],
      bottomLeft: points[3],
    ),
    maxDimension: null,
    output: const scan.ScanOutputFormat.jpegAt(100),
  );
  if (corrected == null ||
      corrected.bytes.length > ScanImageLimits.maxPageBytes ||
      !ScanImageLimits.validDimensions(corrected.width, corrected.height)) {
    throw const ScanFailure(
      'This full-resolution page exceeds 18 MiB or 50 megapixels. Adjust the crop or scan a smaller document area.',
    );
  }
  final decoded = img.decodeJpg(corrected.bytes)!;
  final thumb = _smallJpeg(decoded, 400, 64 * 1024);
  return CorrectedScanPage(
    corrected.bytes,
    thumb,
    corrected.width,
    corrected.height,
  );
});

Future<_PreparedScanCapture> _prepareCapture(
  String original,
  String target,
) async {
  final file = File(original);
  if (await file.length() > ScanImageLimits.maxInputBytes) {
    throw const ScanFailure('Captured images must be at most 40 MiB.');
  }
  final bytes = await file.readAsBytes();
  final header = img.JpegDecoder().startDecode(bytes);
  if (header == null ||
      !ScanImageLimits.validDimensions(header.width, header.height)) {
    throw const ScanFailure(
      'Captured images must be JPEGs of at most 50 megapixels.',
    );
  }
  final upright = img.decodeJpg(bytes);
  if (upright == null) {
    throw const ScanFailure('The captured image could not be decoded.');
  }
  final preview = _smallJpeg(upright, 1200, ScanImageLimits.maxPreviewBytes);
  await file.delete();
  await File(target).writeAsBytes(bytes, flush: true);
  return _PreparedScanCapture(upright.width, upright.height, preview);
}

Uint8List _smallJpeg(img.Image image, int longSide, int limit) {
  final scale = math.min(1.0, longSide / math.max(image.width, image.height));
  final resized = img.copyResize(
    image,
    width: math.max(1, (image.width * scale).round()),
    height: math.max(1, (image.height * scale).round()),
  );
  for (final quality in [85, 70, 55, 40]) {
    final bytes = img.encodeJpg(resized, quality: quality);
    if (bytes.length <= limit) return bytes;
  }
  throw const ScanFailure('The scan preview exceeds its storage limit.');
}
