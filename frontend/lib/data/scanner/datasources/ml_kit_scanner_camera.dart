import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../domain/scanner/interfaces/scanner_camera.dart';
import '../../../domain/scanner/models/scan.dart';
import '../models/scan_assets.dart';
import '../models/scan_image_limits.dart';
import '../repos/scan_capture_data_port.dart';
import 'scan_draft_store.dart';
import 'scan_storage_coordinator.dart';
import 'processed_scan_page.dart';

final class MlKitScannerCamera
    implements ScanCaptureDataPort, ScannerSystemCapture {
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
  String get systemCaptureNotice =>
      'Scanning uses Google Play services. Images are processed on your device; Google receives scanner usage and performance metrics.';
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
        () => prepareProcessedScanPage(bytes),
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
      throw _scannerFailure(error);
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
          () => createProcessedScanThumbnail(bytes),
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

ScanFailure _scannerFailure(PlatformException error) {
  final message = switch (error.code) {
    'scan_too_large' =>
      'This scanned page exceeds 18 MiB. Scan a smaller document area.',
    'scan_unsupported' =>
      'Google document scanning is not supported on this device.',
    'scan_play_services_missing' => 'Google Play services is missing in this Android profile. Install it in this profile to use document scanning.',
    'scan_play_services_update_required' =>
      'Google Play services needs an update before document scanning can open.',
    'scan_play_services_disabled' => 'Google Play services is disabled. Enable it in Android settings, then try again.',
    'scan_play_services_updating' => 'Google Play services is updating. Wait for the update to finish, then try again.',
    'scan_play_services_invalid' => 'Android could not verify this installation of Google Play services. Check its status in Android settings.',
    'scan_network_error' => 'Google document scanning could not connect. Check your internet connection, then try again.',
    'scan_busy' =>
      'A scan is already open. Finish or cancel it, then try again.',
    'scan_activity_unavailable' =>
      'The scanner screen is closing. Open the draft again to scan a page.',
    'scan_restart_required' => 'Restart Domabas before scanning again.',
    'scan_result_invalid' || 'scan_read_failed' || 'scan_failed' =>
      'The scanned page could not be read. Scan this page again.',
    _ => 'Google document scanning could not open. Try again.',
  };
  final reference = <String>[];
  final details = error.details;
  if (details is Map) {
    final stage = details['stage'];
    if (stage is String &&
        const {'prepare', 'launch', 'result', 'read'}.contains(stage)) {
      reference.add(stage);
    }
    for (final (key, label) in const [
      ('mlKitCode', 'ML Kit'),
      ('apiStatus', 'API'),
      ('playServicesStatus', 'Play services'),
      ('resultCode', 'result'),
    ]) {
      final value = details[key];
      if (value is int && value >= -1 && value <= 99999) {
        reference.add('$label $value');
      }
    }
  }
  return ScanFailure(
    reference.isEmpty
        ? message
        : '$message Error reference: ${reference.join(' / ')}.',
  );
}
