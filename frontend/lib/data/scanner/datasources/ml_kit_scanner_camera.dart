import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../../domain/scanner/models/scan.dart';
import '../models/scan_assets.dart';
import '../models/scan_image_limits.dart';
import '../repos/scan_capture_data_port.dart';
import 'scan_draft_store.dart';
import 'scan_storage_coordinator.dart';

final class MlKitScannerCamera implements ScanCaptureDataPort {
  MlKitScannerCamera(
    this.lease, {
    this.channel = const MethodChannel('dev.domabas/document_scanner'),
  });

  final ScanStorageLease lease;
  final MethodChannel channel;
  final _states = StreamController<ScanCameraState>.broadcast();
  ScanCameraState _state = const ScanCameraState();
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  bool _cancelled = false;
  String? _requestId;
  String? _capturePath;
  ScanCapture? _capture;
  ScanReservation? _reservation;
  void Function()? _releaseCamera;

  @override
  bool get usesSystemCapture => true;
  @override
  ScanCameraState get state => _state;
  @override
  Stream<ScanCameraState> get states => _states.stream;

  Future<T> _run<T>(Future<T> Function() operation, {bool cleanup = false}) {
    final result = _tail.then((_) {
      if (!cleanup) _checkActive();
      return operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _checkActive() {
    if (_cancelled || lease.cancelled) {
      throw const ScanCancelled();
    }
  }

  void _emit(ScanCameraStatus status) {
    _state = ScanCameraState(status: status);
    if (!_cancelled) _states.add(_state);
  }

  @override
  Future<void> start() => _run(() async {
    if (_state.status == ScanCameraStatus.ready || _capture != null) return;
    _emit(ScanCameraStatus.starting);
    try {
      _releaseCamera = await lease.coordinator.acquireCamera();
      _checkActive();
      _reservation = await lease.reserve(
        ScanImageLimits.captureReservationBytes,
        scratch: true,
      );
      lease.scratchBytes += ScanImageLimits.captureReservationBytes;
      _checkActive();
      _emit(ScanCameraStatus.ready);
    } catch (_) {
      await _releaseInput();
      _releaseCamera?.call();
      _releaseCamera = null;
      _emit(ScanCameraStatus.unavailable);
      rethrow;
    }
  });

  @override
  Future<ScanCapture> capture() => _run(() async {
    if (_state.status != ScanCameraStatus.ready || _reservation == null) {
      throw const ScanFailure('Open the scanner before capturing a page.');
    }
    final id = ScanDraftStore.newId();
    _requestId = id;
    _emit(ScanCameraStatus.capturing);
    try {
      final bytes = await channel.invokeMethod<Uint8List>('scan', {'id': id});
      _checkActive();
      if (bytes == null) throw const ScanCancelled();
      if (bytes.isEmpty || bytes.length > ScanImageLimits.maxPageBytes) {
        throw const ScanFailure(
          'Scanned pages must be JPEGs of at most 18 MiB.',
        );
      }
      _emit(ScanCameraStatus.processing);
      final prepared = await lease.coordinator.imageWork(
        () => _preparePageInBackground(bytes),
      );
      _checkActive();
      final file = File('${lease.directory.path}/scratch-$id.jpg');
      _capturePath = file.path;
      await file.writeAsBytes(bytes, flush: true);
      _checkActive();
      final capture = ScanCapture(
        id: id,
        width: prepared.width,
        height: prepared.height,
        corners: ScanCorners.fullImage(),
        preview: prepared.preview,
        processed: true,
      );
      _capture = capture;
      return capture;
    } on PlatformException catch (error) {
      await _releaseInput();
      if (error.code == 'scan_cancelled') throw const ScanCancelled();
      throw ScanFailure(switch (error.code) {
        'scan_too_large' =>
          'This scanned page exceeds 18 MiB. Scan a smaller document area.',
        'scan_unsupported' =>
          'Google document scanning is not supported on this device.',
        _ => 'Google document scanning could not start or finish. Check that Google Play services is installed and up to date, connect to the internet for the first scan, then try again.',
      });
    } catch (_) {
      await _releaseInput();
      rethrow;
    } finally {
      _requestId = null;
      _releaseCamera?.call();
      _releaseCamera = null;
      _emit(ScanCameraStatus.suspended);
    }
  });

  @override
  Future<CorrectedScanPage> correct(ScanCapture capture, ScanCorners corners) =>
      _run(() async {
        final saved = _capture;
        if (saved == null ||
            saved.id != capture.id ||
            saved.width != capture.width ||
            saved.height != capture.height ||
            _capturePath == null) {
          throw const ScanFailure('Scan this page again.');
        }
        final file = File(_capturePath!);
        if (await file.length() > ScanImageLimits.maxPageBytes) {
          throw const ScanFailure('Scanned pages must be at most 18 MiB.');
        }
        final bytes = await file.readAsBytes();
        final thumbnail = await lease.coordinator.imageWork(
          () => _thumbnailInBackground(bytes),
        );
        _checkActive();
        return CorrectedScanPage(bytes, thumbnail, saved.width, saved.height);
      });

  @override
  Future<void> releaseCapture(String id) => _run(() async {
    if (_capture?.id == id) await _releaseInput();
  }, cleanup: true);

  Future<void> _releaseInput() async {
    if (_capturePath case final path?) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _capturePath = null;
    _capture = null;
    if (_reservation != null) {
      lease.scratchBytes -= ScanImageLimits.captureReservationBytes;
      _reservation!.release();
      _reservation = null;
    }
  }

  @override
  Future<void> suspend() => _run(() async {
    if (_capture == null) await _releaseInput();
    _releaseCamera?.call();
    _releaseCamera = null;
    _emit(ScanCameraStatus.suspended);
  }, cleanup: true);

  @override
  void cancelNewOperations() {
    if (_cancelled) return;
    _cancelled = true;
    if (_requestId case final id?) {
      unawaited(
        channel
            .invokeMethod<void>('cancel', {'id': id})
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  @override
  Future<void> close() {
    cancelNewOperations();
    return _closing ??= _run(() async {
      try {
        await _releaseInput();
      } finally {
        _releaseCamera?.call();
        _releaseCamera = null;
        await _states.close();
      }
    }, cleanup: true);
  }
}

Future<({int width, int height, Uint8List preview})> _preparePageInBackground(
  Uint8List bytes,
) => Isolate.run(() => _preparePage(bytes));

Future<Uint8List> _thumbnailInBackground(Uint8List bytes) => Isolate.run(
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

({int width, int height, Uint8List preview}) _preparePage(Uint8List bytes) {
  final image = _decodePage(bytes);
  return (
    width: image.width,
    height: image.height,
    preview: _preview(image, 1200, ScanImageLimits.maxPreviewBytes),
  );
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
